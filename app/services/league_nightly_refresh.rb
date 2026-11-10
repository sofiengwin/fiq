# L6: Nightly stale-only refresh — heals data without re-pulling everything.
#
# Live-only: every stale row costs one live FootballClient read against
# max_requests (default 200); there is no response cache, so reruns are
# full-cost but idempotent. Selects only rows whose `last_refreshed_at`
# (PL 39-linked rows first), re-syncs each via the live FootballClient,
# and touches `last_refreshed_at` on success. Fresh rows are never
# touched. Each stale row costs one live client read against `max_requests`
# (default 200).
#
# Dry-run mode counts would-refresh rows per table and performs zero HTTP,
# zero DB writes, and zero enqueues. The pre-quiz staleness gate stays
# deferred — this never blocks quiz paths.
# L9: a refreshed stale team that is still bare (no players) and linked to
# an in-scope league gets its squad fetch enqueued (FetchTeamPlayersJob,
# zero HTTP now, fetched live when the job runs), so career-path bare teams
# gain squads within one nightly cycle.
class LeagueNightlyRefresh < ApplicationService
  LEAGUE_ID = 39
  COMPETITION_EXTERNAL_ID = "39"
  DEFAULT_MAX_REQUESTS = 200
  STALE_AFTER = 30.days

  BudgetExhausted = Class.new(StandardError)

  def initialize(dry_run: false, max_requests: DEFAULT_MAX_REQUESTS, league_id: LEAGUE_ID)
    @dry_run = dry_run
    @max_requests = max_requests.to_i
    @league_id = league_id.to_i
    @now = Time.current
    @threshold = STALE_AFTER.ago
    @live_requests = 0
    @skipped_count = 0
    @failed_count = 0
    @squads_enqueued = 0
    @halted = false
  end

  def call
    result = {
      status: :completed, dry_run: @dry_run, league_id: @league_id,
      teams: 0, players: 0, careers: 0, total: 0,
      live_requests: 0, capped: false, skipped: 0, failed: 0,
      squads_enqueued: 0
    }

    teams_scope = FootballTeam.stale(@threshold)
    players_scope = Player.stale(@threshold)
    careers_scope = Career.stale(@threshold)
    result[:total] = teams_scope.count + players_scope.count + careers_scope.count

    if @dry_run
      result.merge!(
        teams: teams_scope.count,
        players: players_scope.count,
        careers: careers_scope.count
      )
      Rails.logger.info("LeagueNightlyRefresh dry-run #{summary_line(result)}")
      return result
    end

    refreshed = { teams: 0, players: 0, careers: 0 }
    refreshed[:teams] = refresh_teams(teams_scope)
    refreshed[:players] = refresh_players(players_scope)
    refreshed[:careers] = refresh_careers(careers_scope)
    result.merge!(refreshed)
    result[:live_requests] = @live_requests
    result[:skipped] = @skipped_count
    result[:failed] = @failed_count
    result[:squads_enqueued] = @squads_enqueued

    visited = refreshed.values.sum + result[:skipped] + result[:failed]
    result[:capped] = visited < result[:total]
    if result[:capped]
      Rails.logger.warn("LeagueNightlyRefresh capped at #{@max_requests} live requests (resume-safe rerun) #{summary_line(result)}")
    else
      Rails.logger.info("LeagueNightlyRefresh complete #{summary_line(result)}")
    end
    result
  end

  private

  def summary_line(result)
    "teams=#{result[:teams]} players=#{result[:players]} careers=#{result[:careers]} " \
      "total=#{result[:total]} live_requests=#{result[:live_requests]} capped=#{result[:capped]}"
  end

  # --- per-table refresh (league-linked rows first) ---------------------------

  def refresh_teams(scope)
    refreshed = 0
    each_league_first(scope, league_team_ids) do |team|
      refreshed += 1 if refresh_team!(team)
    end
    refreshed
  end

  def refresh_players(scope)
    refreshed = 0
    each_league_first(scope, league_player_ids) do |player|
      refreshed += 1 if refresh_player!(player)
    end
    refreshed
  end

  def refresh_careers(scope)
    refreshed = 0
    each_league_first(scope, league_career_ids) do |career|
      refreshed += 1 if refresh_career!(career)
    end
    refreshed
  end

  # Yields stale rows league-first (then by id), stopping cleanly when the live
  # budget is spent. Empty league_ids degrades to a single id-ordered pass, so
  # rows are never filtered out when no league linkage exists yet.
  def each_league_first(scope, league_ids)
    [ scope.where(id: league_ids).order(:id), scope.where.not(id: league_ids).order(:id) ].each do |partition|
      partition.find_each(batch_size: 100) do |record|
        break if budget_exhausted? || @halted
        yield record
      end
      break if budget_exhausted? || @halted
    end
  end

  def budget_exhausted?
    @live_requests >= @max_requests
  end

  # --- per-row re-sync (one live-client read, then touch) -------------------

  def refresh_team!(team)
    if team.external_id.blank?
      skip_row("team id=#{team.id} has no external_id; leaving stale")
      return false
    end
    fetch_counted("teams?id=#{team.external_id}")
    team.update!(last_refreshed_at: @now)
    enqueue_bare_squad!(team)
    true
  rescue BudgetExhausted
    raise
  rescue StandardError => e
    fail_row("team id=#{team.id}", e)
    false
  end

  # L9 acceptance: a career-path bare team (stale, refreshed above, still
  # no players) gains its squad within one nightly cycle — the enqueue
  # itself is zero HTTP; the squad fetch runs live when the job executes
  # (quota exhaustion backs off via retry_on and the row retries on the
  # next nightly). Only positively
  # in-scope teams qualify (L8 precedent: unknown scope fetches the
  # profile but never auto-enqueues); out-of-scope and curator-pending
  # rows stay pending-manual.
  def enqueue_bare_squad!(team)
    return if Career.where(football_team: team).exists?
    return unless squad_enqueue_allowed?(team)

    FetchTeamPlayersJob.perform_later(team.id)
    @squads_enqueued += 1
    Rails.logger.info("LeagueNightlyRefresh enqueued squad for bare team id=#{team.id}")
  end

  def squad_enqueue_allowed?(team)
    league_ids = team.competitions.map { |competition| competition.external_id.to_i }
    return false if league_ids.empty?

    league_ids.any? { |id| AutoDiscovery.in_scope_league?(id) }
  end

  def refresh_player!(player)
    if player.external_id.blank?
      skip_row("player id=#{player.id} has no external_id; leaving stale")
      return false
    end
    fetch_counted("players/profiles?player=#{player.external_id}")
    player.update!(last_refreshed_at: @now)
    true
  rescue BudgetExhausted
    raise
  rescue StandardError => e
    fail_row("player id=#{player.id}", e)
    false
  end

  def refresh_career!(career)
    if career.player&.external_id.blank?
      skip_row("career id=#{career.id} has no player external_id; leaving stale")
      return false
    end
    fetch_counted("players/teams?player=#{career.player.external_id}")
    career.update!(last_refreshed_at: @now)
    true
  rescue BudgetExhausted
    raise
  rescue StandardError => e
    fail_row("career id=#{career.id}", e)
    false
  end

  # Counts every read against the budget (live-only: no response cache, so
# each stale row costs one live request). Errors other than rate limits
# are counted per-row by the callers; a rate limit propagates so the job
# can back off and retry (LeagueTeamsJob precedent) instead of burning
# the budget on guaranteed failures.
  def fetch_counted(endpoint)
    raise BudgetExhausted if budget_exhausted?

    @live_requests += 1
    FootballClient.call(end_point: endpoint)
  end

  def skip_row(message)
    @skipped_count += 1
    Rails.logger.warn("LeagueNightlyRefresh skipping #{message}")
  end

  def fail_row(label, error)
    raise error if error.is_a?(FootballClient::FootballClientRateLimitExceeded)

    @failed_count += 1
    Rails.logger.error("LeagueNightlyRefresh failed #{label}: #{error.message}")
  end

  # --- league-first partitions -------------------------------------------------

  def league_competition_id
    @league_competition_id ||= Competition.find_by(external_id: @league_id.to_s)&.id
  end

  def league_team_ids
    @league_team_ids ||=
      if league_competition_id
        FootballTeam.joins(:competitions).where(competitions: { id: league_competition_id }).distinct.pluck(:id)
      else
        []
      end
  end

  def league_player_ids
    @league_player_ids ||= begin
      scopes = []
      scopes << Career.where(football_team_id: league_team_ids) if league_team_ids.any?
      scopes << Career.where(competition_id: league_competition_id) if league_competition_id

      if scopes.empty?
        []
      else
        scopes.reduce { |combined, scope| combined.or(scope) }.distinct.pluck(:player_id)
      end
    end
  end

  def league_career_ids
    @league_career_ids ||= begin
      scopes = []
      scopes << Career.where(football_team_id: league_team_ids) if league_team_ids.any?
      scopes << Career.where(competition_id: league_competition_id) if league_competition_id

      if scopes.empty?
        []
      else
        scopes.reduce { |combined, scope| combined.or(scope) }.pluck(:id)
      end
    end
  end
end

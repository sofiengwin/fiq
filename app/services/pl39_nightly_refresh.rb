# T7: Nightly stale-only refresh — heals data without re-pulling everything.
#
# Selects only rows whose `last_refreshed_at` is nil or older than 30 days
# (PL 39-linked rows first), re-syncs each via the cached FootballClient
# (T2), and touches `last_refreshed_at` on success. Fresh rows are never
# touched. Each stale row costs at most one client read, and only
# would-be-live reads count against `max_requests` (default 200): cached
# replays are free, so an immediate rerun costs ~0 live requests and a
# capped run resumes cleanly on the next invocation.
#
# Dry-run mode counts would-refresh rows per table and performs zero HTTP,
# zero DB writes, and zero enqueues. The pre-quiz staleness gate stays
# deferred — this never blocks quiz paths.
class Pl39NightlyRefresh < ApplicationService
  LEAGUE_ID = 39
  COMPETITION_EXTERNAL_ID = "39"
  DEFAULT_MAX_REQUESTS = 200
  STALE_AFTER = 30.days

  BudgetExhausted = Class.new(StandardError)

  def initialize(dry_run: false, max_requests: DEFAULT_MAX_REQUESTS)
    @dry_run = dry_run
    @max_requests = max_requests.to_i
    @now = Time.current
    @threshold = STALE_AFTER.ago
    @live_requests = 0
    @skipped_count = 0
    @failed_count = 0
    @halted = false
  end

  def call
    result = {
      status: :completed, dry_run: @dry_run,
      teams: 0, players: 0, careers: 0, total: 0,
      live_requests: 0, capped: false, skipped: 0, failed: 0
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
      Rails.logger.info("Pl39NightlyRefresh dry-run #{summary_line(result)}")
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

    visited = refreshed.values.sum + result[:skipped] + result[:failed]
    result[:capped] = visited < result[:total]
    if result[:capped]
      Rails.logger.warn("Pl39NightlyRefresh capped at #{@max_requests} live requests (resume-safe rerun) #{summary_line(result)}")
    else
      Rails.logger.info("Pl39NightlyRefresh complete #{summary_line(result)}")
    end
    result
  end

  private

  def summary_line(result)
    "teams=#{result[:teams]} players=#{result[:players]} careers=#{result[:careers]} " \
      "total=#{result[:total]} live_requests=#{result[:live_requests]} capped=#{result[:capped]}"
  end

  # --- per-table refresh (PL 39-linked rows first) ---------------------------

  def refresh_teams(scope)
    refreshed = 0
    each_pl_first(scope, pl_team_ids) do |team|
      refreshed += 1 if refresh_team!(team)
    end
    refreshed
  end

  def refresh_players(scope)
    refreshed = 0
    each_pl_first(scope, pl_player_ids) do |player|
      refreshed += 1 if refresh_player!(player)
    end
    refreshed
  end

  def refresh_careers(scope)
    refreshed = 0
    each_pl_first(scope, pl_career_ids) do |career|
      refreshed += 1 if refresh_career!(career)
    end
    refreshed
  end

  # Yields stale rows PL-first (then by id), stopping cleanly when the live
  # budget is spent. Empty pl_ids degrades to a single id-ordered pass, so
  # rows are never filtered out when no PL linkage exists yet.
  def each_pl_first(scope, pl_ids)
    [ scope.where(id: pl_ids).order(:id), scope.where.not(id: pl_ids).order(:id) ].each do |partition|
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

  # --- per-row re-sync (one cached-client read, then touch) -------------------

  def refresh_team!(team)
    if team.external_id.blank?
      skip_row("team id=#{team.id} has no external_id; leaving stale")
      return false
    end
    fetch_counted("teams?id=#{team.external_id}")
    team.update!(last_refreshed_at: @now)
    true
  rescue BudgetExhausted
    raise
  rescue StandardError => e
    fail_row("team id=#{team.id}", e)
    false
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

  # Counts only would-be-live reads against the budget (mirrors T5): rows
  # already in the T2 cache replay for free. Errors other than rate limits
  # are counted per-row by the callers; a rate limit propagates so the job
  # can back off and retry (LeagueTeamsJob precedent) instead of burning
  # the budget on guaranteed failures.
  def fetch_counted(endpoint)
    return FootballClient.call(end_point: endpoint) if File.exist?(FootballClient.cache_path_for(endpoint))

    raise BudgetExhausted if budget_exhausted?

    @live_requests += 1
    FootballClient.call(end_point: endpoint)
  end

  def skip_row(message)
    @skipped_count += 1
    Rails.logger.warn("Pl39NightlyRefresh skipping #{message}")
  end

  def fail_row(label, error)
    raise error if error.is_a?(FootballClient::FootballClientRateLimitExceeded)

    @failed_count += 1
    Rails.logger.error("Pl39NightlyRefresh failed #{label}: #{error.message}")
  end

  # --- PL 39-first partitions -------------------------------------------------

  def pl_competition_id
    @pl_competition_id ||= Competition.find_by(external_id: COMPETITION_EXTERNAL_ID)&.id
  end

  def pl_team_ids
    @pl_team_ids ||=
      if pl_competition_id
        FootballTeam.joins(:competitions).where(competitions: { id: pl_competition_id }).distinct.pluck(:id)
      else
        []
      end
  end

  def pl_player_ids
    @pl_player_ids ||= begin
      scopes = []
      scopes << Career.where(football_team_id: pl_team_ids) if pl_team_ids.any?
      scopes << Career.where(competition_id: pl_competition_id) if pl_competition_id

      if scopes.empty?
        []
      else
        scopes.reduce { |combined, scope| combined.or(scope) }.distinct.pluck(:player_id)
      end
    end
  end

  def pl_career_ids
    @pl_career_ids ||= begin
      scopes = []
      scopes << Career.where(football_team_id: pl_team_ids) if pl_team_ids.any?
      scopes << Career.where(competition_id: pl_competition_id) if pl_competition_id

      if scopes.empty?
        []
      else
        scopes.reduce { |combined, scope| combined.or(scope) }.pluck(:id)
      end
    end
  end
end

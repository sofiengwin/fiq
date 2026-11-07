require "json"

# T5: Capped backfill batch — one allowlisted PL 39 season per invocation.
#
# Reads seasons_allowlist_39.json (T3) and refuses seasons that are missing,
# past the present year, or not on the allowlist (dead seasons included)
# before any live request. For an allowlisted season it pulls
# teams?league=39&season, then the paginated players?team=<id>&season union
# (~40 reqs/season), and upserts team/player/career skeleton rows with
# competition_id set and last_refreshed_at touched.
#
# Budget: hard stop at max_requests (default 500) live requests per
# invocation. Only would-be-live calls count against the budget — cached
# replays are free — so an immediate rerun makes ~0 live requests and a
# capped run resumes cleanly on the next invocation.
#
# This path never enqueues other seasons and never uses LeagueTeamsJob (its
# season+1 self-recursion is left intact for later tickets, just not used
# here). Detailed career stats stay in T6; this ticket only guarantees the
# base skeleton + linkage so T4 can measure completeness.
class Pl39Backfill < ApplicationService
  LEAGUE_ID = 39
  COMPETITION_NAME = "Premier League"
  DEFAULT_MAX_REQUESTS = 500

  BudgetExhausted = Class.new(StandardError)

  def initialize(season:, league_id: LEAGUE_ID, present_year: Time.zone.now.year, max_requests: DEFAULT_MAX_REQUESTS,
    raw_dir: Rails.root.join("data/raw"))
    @season = season.to_i
    @league_id = league_id.to_i
    @present_year = present_year.to_i
    @max_requests = max_requests.to_i
    @raw_dir = Pathname.new(raw_dir.to_s)
  end

  def call
    refusal = refusal_reason
    return refused_result(refusal) if refusal

    @live_requests = 0
    @now = Time.current
    @team_rows = []
    @player_ids = {}
    @careers_created = 0

    teams_payload = Array(fetch_counted("teams?league=#{@league_id}&season=#{@season}"))
    competition = find_or_create_competition!(teams_payload)
    @team_rows = teams_payload.filter_map { |row| upsert_team!(row, competition) }
    @team_rows.each do |team, team_api_id|
      @careers_created += upsert_team_players!(team, team_api_id, competition)
    end

    completed_result
  rescue BudgetExhausted
    capped_result
  end

  private

  # --- gating (zero HTTP, zero DB writes) ---------------------------------

  def refusal_reason
    return missing_season_reason if @season <= 0
    if @season > @present_year
      return "season #{@season} is past present year #{@present_year}; refusing future-season fetch"
    end

    allowlist = read_allowlist
    return "no #{Pl39Probe.allowlist_filename_for(@league_id)} in #{@raw_dir}; run #{probe_task_hint} first" if allowlist.nil?

    unless allowlist.include?(@season)
      dead_reason = dead_reason_for(@season)
      return "season #{@season} is dead (#{dead_reason}); never bulk-pulled" if dead_reason

      return "season #{@season} is not on the #{league_label} allowlist #{allowlist.inspect}"
    end

    nil
  end

  def league_label
    @league_id == LEAGUE_ID ? "PL 39" : "league #{@league_id}"
  end

  def missing_season_reason
    hint = @league_id == LEAGUE_ID ? "data:backfill_pl39[season]" : "data:backfill_league[#{@league_id},season]"
    "missing season (pass #{hint})"
  end

  def probe_task_hint
    @league_id == LEAGUE_ID ? "data:probe_pl39" : "data:probe_league[#{@league_id}]"
  end

  def read_allowlist
    path = @raw_dir.join(Pl39Probe.allowlist_filename_for(@league_id))
    return nil unless File.exist?(path)

    parsed = JSON.parse(File.read(path))
    return nil unless parsed.is_a?(Array)

    parsed.map(&:to_i)
  rescue JSON::ParserError
    nil
  end

  def dead_reason_for(season)
    path = @raw_dir.join(Pl39Probe.dead_filename_for(@league_id))
    return nil unless File.exist?(path)

    parsed = JSON.parse(File.read(path))
    return nil unless parsed.is_a?(Array)

    entry = parsed.find { |row| row.is_a?(Hash) && row["season"].to_i == season }
    entry&.fetch("reason", "listed without reason")
  rescue JSON::ParserError
    nil
  end

  # --- budgeted fetching (cache-first, T2) ----------------------------------

  # Counts only would-be-live calls against the budget: entries already in
  # the T2 cache replay for free, so reruns cost ~0 and capped runs resume.
  def fetch_counted(endpoint)
    cached = File.exist?(FootballClient.cache_path_for(endpoint))
    raise BudgetExhausted if !cached && @live_requests >= @max_requests

    result = FootballClient.call(end_point: endpoint)
    @live_requests += 1 unless cached
    result
  end

  # Paging comes from the cached raw envelope (FootballClient returns only
  # the response array). Without a cache file (cache disabled) fall back to
  # stopping on the first empty page; the budget bounds that walk.
  def last_page?(endpoint, entries)
    paging = paging_for(endpoint)
    return entries.empty? if paging.nil?

    paging[:current] >= paging[:total]
  end

  def paging_for(endpoint)
    path = FootballClient.cache_path_for(endpoint)
    return nil unless File.exist?(path)

    paging = JSON.parse(File.read(path))["paging"]
    return nil unless paging.is_a?(Hash)

    { current: paging["current"].to_i, total: paging["total"].to_i }
  rescue JSON::ParserError
    nil
  end

  # --- upserts (team/player/career + stats incl. appearances; T6/T8) --------

  def find_or_create_competition!(teams_payload)
    first = teams_payload.filter_map { |row| row[:team] }.find { |team| team[:id] }
    country_name = first&.dig(:country).presence || "Unknown"
    country = Country.find_or_create_by!(name: country_name)
    Competition.find_or_create_by!(external_id: @league_id.to_s) do |competition|
      competition.name = @league_id == LEAGUE_ID ? COMPETITION_NAME : "League #{@league_id}"
      competition.country = country
    end
  end

  def upsert_team!(row, competition)
    data = row[:team] || {}
    api_id = data[:id]
    return nil if api_id.nil?

    country = Country.find_or_create_by!(name: data[:country].presence || "Unknown")
    team = UpsertTeam.call(
      external_id: api_id,
      name: data[:name].presence || "Team #{api_id}",
      code: data[:code],
      country: country,
      national: data[:national] || false,
      competition: competition
    )
    team.update!(last_refreshed_at: @now)
    [ team, api_id ]
  end

  def upsert_team_players!(team, team_api_id, competition)
    created = 0
    page = 1
    loop do
      endpoint = "players?team=#{team_api_id}&season=#{@season}&page=#{page}"
      entries = Array(fetch_counted(endpoint))
      entries.each do |entry|
        api_id = entry.dig(:player, :id)
        next if api_id.nil?

        player = upsert_player!(entry[:player])
        @player_ids[api_id] ||= player
        created += 1 if upsert_career!(player, team, competition, entry[:statistics], team_api_id)
      end
      break if last_page?(endpoint, entries)

      page += 1
    end
    created
  end

  # T6: quiz-required profile fill from the player payload. dob/nationality/
  # photo_url stay nullable so a sparse profile still saves; missing fields
  # are flagged in the logs, never silently dropped.
  def upsert_player!(data)
    player = Player.find_or_create_by!(external_id: data[:id].to_s) do |record|
      record.name = data[:name].presence || "Player #{data[:id]}"
    end
    attrs = {
      name: data[:name].presence || player.name,
      dob: parse_dob(data.dig(:birth, :date)),
      nationality: data[:nationality].presence,
      photo_url: (data[:photo].presence || data[:photo_url].presence),
      last_refreshed_at: @now
    }
    missing = %i[dob nationality photo_url].select { |key| attrs[key].nil? }
    unless missing.empty?
      Rails.logger.warn(
        "Pl39Backfill incomplete profile player=#{player.external_id} " \
        "missing=#{missing.join(",")}"
      )
    end
    player.update!(attrs)
    player
  end

  # T6/T8: quiz-required stat fill from the inline statistics payload.
  # goals is mandatory: a missing goals value defaults to 0 so every union
  # player still gets a career row for the backfilled season (sparse stats
  # never leave a player career-less). assists/cards stay nullable.
  # appearances is wired from games.appearences (API typo) / games.appearances.
  # competition_id points at the PL competition.
  def upsert_career!(player, team, competition, statistics, team_api_id)
    stat = select_team_stat(statistics, team_api_id)
    goals = stat&.dig(:goals, :total)
    if goals.nil?
      Rails.logger.warn(
        "Pl39Backfill defaulting missing goals to 0 " \
        "player=#{player.external_id} team=#{team.external_id} season=#{@season}"
      )
      goals = 0
    end
    appearances = stat&.dig(:games, :appearences) || stat&.dig(:games, :appearances) || 0

    career = Career.find_or_create_by!(player: player, football_team: team) do |record|
      record.duration = season_range
    end
    created = career.previously_new_record?
    career.update!(
      competition_id: competition.id,
      goals: goals,
      assists: stat&.dig(:goals, :assists),
      cards_yellow: stat&.dig(:cards, :yellow),
      cards_red: stat&.dig(:cards, :red),
      appearances: appearances.to_i,
      last_refreshed_at: @now
    )
    created
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error(
      "Pl39Backfill career rejected player=#{player.external_id} " \
      "team=#{team.external_id} season=#{@season}: #{e.message}"
    )
    false
  end

  # The union response can carry several statistics rows (e.g. a mid-season
  # mover); prefer the row for the team being unioned so goals/assists/cards
  # belong to this club. Fall back to the first row when nothing matches.
  def select_team_stat(statistics, team_api_id)
    stats = Array(statistics)
    return nil if stats.empty?

    stats.find { |row| row.dig(:team, :id).to_i == team_api_id.to_i } || stats.first
  end

  def parse_dob(value)
    return nil if value.nil? || value.to_s.strip.empty?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Football-season window (Jul 1 -> Jul 1 exclusive): consecutive seasons
  # stay adjacent without overlapping, so reruns and multi-season backfills
  # never trip the same-team overlap validation.
  def season_range
    Date.new(@season, 7, 1)...Date.new(@season + 1, 7, 1)
  end

  # --- results ----------------------------------------------------------------

  def refused_result(reason)
    Rails.logger.warn("Pl39Backfill league=#{@league_id} refused season=#{@season}: #{reason}")
    { status: :refused, league_id: @league_id, season: @season, live_requests: 0, refusal_reason: reason }
  end

  def completed_result
    summary = {
      status: :completed, league_id: @league_id, season: @season, live_requests: @live_requests,
      teams: @team_rows.size, players: @player_ids.size,
      careers: @careers_created, capped: false
    }
    Rails.logger.info("Pl39Backfill complete #{summary.inspect}")
    summary
  end

  def capped_result
    summary = {
      status: :capped, league_id: @league_id, season: @season, live_requests: @live_requests,
      teams: @team_rows.size, players: @player_ids.size,
      careers: @careers_created, capped: true
    }
    Rails.logger.warn("Pl39Backfill capped at #{@max_requests} live requests (resume-safe rerun) #{summary.inspect}")
    summary
  end
end

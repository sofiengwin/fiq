class UpsertPlayerCareer < ApplicationService
  RESERVE_TEAM_PATTERNS = [
    /\sB$/i,           # Porto B, Barcelona B
    /\sII$/i,          # German reserve teams
    /\sU\d{2}$/i,      # U21, U23
    /\sCastilla$/i,    # Real Madrid Castilla
    /\sReserves?$/i,   # Manchester United Reserves
    /\sYouth$/i,       # Youth teams
    /\sJuvenil$/i,     # Spanish youth
    /\sJunior/i       # Junior teams
  ].freeze

  def initialize(player:, team: nil, league_id: nil)
    @player = player
    @team = team
    @league_id = league_id
  end

  def call
    career_teams_data = fetch_player_teams
    career_teams = career_teams_data || []

    return if career_teams.blank?

    # Build transfer date lookup from transfers endpoint
    @transfer_dates = build_transfer_date_lookup
    pp @transfer_dates

    # Process career teams with season gap detection
    # Uses transfer dates to determine precise start_date and end_date
    process_career_teams_with_gaps(career_teams)

    @player.careers.reload
  rescue AutoDiscovery::OverBudget => e
    # L8: budget spent mid-run — keep partial careers (idempotent rerun
    # resumes), stay pending with zero further HTTP.
    AutoDiscovery.note("pending-budget", player: @player.external_id, reason: e.message)
    @player.careers.reload
  rescue StandardError => e
    Rails.logger.error("UpsertPlayerCareer failed for player #{@player.id}: #{e.message}")
    raise e
  end

  private

  # L8: every auto HTTP call spends one auto-budget request first; over
  # budget raises before any HTTP happens.
  def auto_fetch(endpoint)
    AutoDiscovery.checkout!
    FootballClient.call(end_point: endpoint)
  end

  def fetch_player_transfers
    auto_fetch("transfers?player=#{@player.external_id}")
  end

  def fetch_player_teams
    auto_fetch("players/teams?player=#{@player.external_id}")
  end

  def extract_transfers(response)
    return [] if response.blank? || response[0].nil?
    response[0][:transfers] || []
  end

  def fetch_team_profile(team_id:)
    auto_fetch("teams?id=#{team_id}")
  end

  # Build a lookup of transfer dates by team_id
  # Returns { team_id => { arrivals: [dates], departures: [dates] } }
  def build_transfer_date_lookup
    transfers_data = fetch_player_transfers
    transfers = extract_transfers(transfers_data)
    return {} if transfers.blank?

    lookup = Hash.new { |h, k| h[k] = { arrivals: [], departures: [] } }

    transfers.each do |transfer|
      date = fmt_date(transfer[:date])
      next unless date

      team_in = transfer.dig(:teams, :in)
      team_out = transfer.dig(:teams, :out)

      if team_in && team_in[:id]
        lookup[team_in[:id]][:arrivals] << date
      end

      if team_out && team_out[:id]
        lookup[team_out[:id]][:departures] << date
      end
    end

    # Sort dates for each team
    lookup.each_value do |dates|
      dates[:arrivals].sort!
      dates[:departures].sort!
    end

    lookup
  end

  # Find the best start_date from transfers for a given team and season range
  def find_transfer_start_date(team_id, first_season)
    return nil unless @transfer_dates[team_id]

    arrivals = @transfer_dates[team_id][:arrivals]
    return nil if arrivals.blank?

    season_start = Date.new(first_season, 7, 1)
    season_end = Date.new(first_season + 1, 6, 30)

    # Find arrival closest to or just before the first season
    # Look for arrivals within a reasonable window (1 year before season start to season end)
    window_start = season_start - 1.year
    relevant_arrivals = arrivals.select { |d| d >= window_start && d <= season_end }

    # Return the closest arrival to season start
    relevant_arrivals.min_by { |d| (d - season_start).abs }
  end

  # Find the best end_date from transfers for a given team and season range
  def find_transfer_end_date(team_id, last_season)
    return nil unless @transfer_dates[team_id]

    departures = @transfer_dates[team_id][:departures]
    return nil if departures.blank?

    season_end = Date.new(last_season + 1, 6, 30)

    # Find departure closest to or just after the last season end
    # Look for departures within a reasonable window (season start to 1 year after)
    window_start = Date.new(last_season, 7, 1)
    window_end = season_end + 1.year
    relevant_departures = departures.select { |d| d >= window_start && d <= window_end }

    # Return the closest departure to season end
    relevant_departures.min_by { |d| (d - season_end).abs }
  end

  def senior_team?(team_name)
    return true if team_name.blank?
    RESERVE_TEAM_PATTERNS.none? { |pattern| team_name.match?(pattern) }
  end

  # Process career teams with gap detection to split non-consecutive seasons
  # e.g., seasons [2016, 2017, 2020, 2021] becomes two career entries:
  # - 2016-2018 (first spell)
  # - 2020-2022 (second spell, e.g., after loan return)
  def process_career_teams_with_gaps(career_teams)
    career_teams.each do |team_data|
      team_api_id = team_data.dig(:team, :id)
      next unless team_api_id

      team_name = team_data.dig(:team, :name)
      next unless senior_team?(team_name)

      seasons = team_data[:seasons]
      next if seasons.blank?

      team = find_or_create_team(
        team_external_id: team_api_id,
        team_name: team_data.dig(:team, :name)
      )
      next unless team

      # Group consecutive seasons
      season_groups = group_consecutive_seasons(seasons)

      season_groups.each do |group|
        create_career_for_season_group(team, team_api_id, group)
      end
    end
  end

  # Groups consecutive seasons together
  # [2016, 2017, 2020, 2021] → [[2016, 2017], [2020, 2021]]
  def group_consecutive_seasons(seasons)
    return [] if seasons.blank?

    seasons.map(&:to_i).sort.chunk_while { |a, b| b - a == 1 }.to_a
  end

  def create_career_for_season_group(team, team_api_id, season_group)
    return if season_group.blank?

    first_season = season_group.min
    last_season = season_group.max

    # Try to get precise dates from transfers, fall back to season defaults
    start_date = find_transfer_start_date(team_api_id, first_season) ||
                 Date.new(first_season, 7, 1)

    # End date depends on whether this is the current season
    active_seasons = fetch_active_seasons
    is_current = active_seasons.present? && last_season >= active_seasons.max

    end_date = if is_current
      nil # Still at club
    else
      find_transfer_end_date(team_api_id, last_season) ||
        Date.new(last_season + 1, 6, 30) # End of season
    end

    new_duration = start_date..end_date

    # Check if this exact career already exists
    return if @player.careers.exists?(football_team_id: team.id, duration: new_duration)

    # Only check for overlap with careers at the SAME team
    overlaps_with_same_team = @player.careers
      .where(football_team_id: team.id)
      .any? { |c| careers_overlap?(c.duration, new_duration) }
    return if overlaps_with_same_team

    @player.careers.create!(
      football_team_id: team.id,
      duration: new_duration
    )
  end

  # L8 first-seen: a team unknown by external_id becomes a skeleton row.
  # Its squad is enqueued iff the discovering league context is in scope;
  # out-of-scope (or over-budget) skeletons stay pending with zero further
  # HTTP. Ambiguous/no-match profiles are dead with reason (30d TTL
  # re-check note, logs only). Unknown league context preserves the legacy
  # behavior (fetch profile, full create, no enqueue).
  # L9: dead refusals carry a 30d TTL — inside the window the profile
  # re-fetch is suppressed (zero HTTP); after expiry the row is re-checked.
  def find_or_create_team(team_external_id:, team_name:)
    existing_team = FootballTeam.find_by(external_id: team_external_id)
    return existing_team if existing_team.present?

    scope = discovery_scope
    if scope == :out_of_scope
      team = skeleton_team!(team_external_id, team_name)
      AutoDiscovery.note("pending-manual", kind: "team", external_id: team_external_id, name: team_name)
      return team
    end

    dead_key = "team:#{team_external_id}"
    if AutoDiscovery.dead?(dead_key)
      record = AutoDiscovery.dead_record(dead_key)
      AutoDiscovery.note("dead", kind: "team", external_id: team_external_id, name: team_name,
        reason: record&.dig(:reason), cached: true, recheck_after: AutoDiscovery::DEAD_RECHECK_AFTER.inspect)
      return nil
    end

    team_profile = fetch_team_profile(team_id: team_external_id)
    if team_profile.blank? || team_profile[0].nil? || team_profile[0][:team].nil?
      AutoDiscovery.mark_dead(dead_key, reason: "ambiguous/no-match team profile")
      AutoDiscovery.note("dead", kind: "team", external_id: team_external_id, name: team_name,
        reason: "ambiguous/no-match team profile", recheck_after: AutoDiscovery::DEAD_RECHECK_AFTER.inspect)
      return nil
    end

    AutoDiscovery.clear_dead(dead_key)

    team_data = team_profile[0][:team]
    team = UpsertTeam.call(
      external_id: team_external_id,
      name: team_data[:name],
      code: team_data[:code],
      country: country(name: team_data[:country])
    )

    if scope == :in_scope
      FetchTeamPlayersJob.perform_later(team.id)
      AutoDiscovery.note("enqueued", kind: "squad", team_id: team.id, external_id: team_external_id)
    end
    team
  end

  # L8 league scope for first-seen teams: explicit league_id wins, else the
  # originating squad team's competitions. Unknown when neither is present.
  def discovery_scope
    return AutoDiscovery.in_scope_league?(@league_id) ? :in_scope : :out_of_scope unless @league_id.nil?

    league_ids = @team&.competitions&.map { |competition| competition.external_id.to_i } || []
    return :unknown if league_ids.empty?

    league_ids.any? { |id| AutoDiscovery.in_scope_league?(id) } ? :in_scope : :out_of_scope
  end

  # L8 skeleton: external_id + name only (Unknown country, no competition
  # link, no profile fetch). The career linkage is still built so coverage
  # measures the gap; the squad fill stays pending.
  def skeleton_team!(team_external_id, team_name)
    UpsertTeam.call(
      external_id: team_external_id,
      name: team_name.presence || "Team #{team_external_id}",
      code: nil,
      country: CountryAlias.find_or_create!(CountryAlias::UNKNOWN)
    )
  end

  def fetch_active_seasons
    auto_fetch("players/seasons?player=#{@player.external_id}")
  end

  def country(name:)
    CountryAlias.find_or_create!(name)
  end

  def careers_overlap?(range1, range2)
    return false if range1.nil? || range2.nil?

    start1 = range1.begin
    end1 = range1.end || Date.new(9999, 12, 31)
    start2 = range2.begin
    end2 = range2.end || Date.new(9999, 12, 31)

    return false if start1.nil? || start2.nil?

    # Two ranges overlap if one starts before the other ends
    start1 <= end2 && start2 <= end1
  end

  def fmt_date(date)
    date&.to_date
  rescue ArgumentError
    nil
  end
end

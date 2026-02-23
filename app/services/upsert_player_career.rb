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

  def initialize(player:, team: nil)
    @player = player
    @team = team
  end

  def call
    transfers_data = fetch_player_transfers
    career_teams_data = fetch_player_teams

    transfers = extract_transfers(transfers_data)
    career_teams = career_teams_data || []

    return if transfers.blank? && career_teams.blank?

    sorted_transfers = transfers.sort_by { |t| t[:date] }
    fmt_transfers = format_transfers(sorted_transfers)

    # Process career teams with season gap detection
    # This creates separate career entries for non-consecutive seasons
    process_career_teams_with_gaps(career_teams)

    # Process transfers (preferred source for middle career)
    merged_transfers = merge_consecutive_careers(fmt_transfers)

    merged_transfers.each do |transfer|
      team = find_or_create_team(
        team_external_id: transfer[:id],
        team_name: transfer[:name]
      )
      next if team.nil? || transfer[:start_date].nil?

      new_duration = transfer[:start_date]..transfer[:end_date]

      # Find existing career that overlaps with this transfer period for the SAME team
      existing_career = @player.careers
        .where(football_team_id: team.id)
        .find { |c| careers_overlap?(c.duration, new_duration) }

      if existing_career
        # Update duration if transfer data provides more info
        existing_career.update!(duration: new_duration)
      else
        # Check if this exact career period already exists
        exact_match = @player.careers.find_by(
          football_team_id: team.id,
          duration: new_duration
        )
        next if exact_match

        # Only check for overlap with careers at the SAME team
        overlaps_with_same_team = @player.careers
          .where(football_team_id: team.id)
          .any? { |c| careers_overlap?(c.duration, new_duration) }
        next if overlaps_with_same_team

        @player.careers.create!(
          football_team_id: team.id,
          duration: new_duration
        )
      end
    end

    @player.careers.reload
  rescue StandardError => e
    Rails.logger.error("UpsertPlayerCareer failed for player #{@player.id}: #{e.message}")
    raise e
  end

  private

  def fetch_player_transfers
    FootballClient.call(end_point: "transfers?player=#{@player.external_id}")
  end

  def fetch_player_teams
    FootballClient.call(end_point: "players/teams?player=#{@player.external_id}")
  end

  def extract_transfers(response)
    return [] if response.blank? || response[0].nil?
    response[0][:transfers] || []
  end

  def fetch_team_profile(team_id:)
    FootballClient.call(end_point: "teams?id=#{team_id}")
  end

  # Process career teams with gap detection to split non-consecutive seasons
  # e.g., seasons [2016, 2017, 2020, 2021] becomes two career entries:
  # - 2016-2018 (first spell)
  # - 2020-2022 (second spell, e.g., after loan return)
  def senior_team?(team_name)
    return true if team_name.blank?
    RESERVE_TEAM_PATTERNS.none? { |pattern| team_name.match?(pattern) }
  end

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
        create_career_for_season_group(team, group)
      end
    end
  end

  # Groups consecutive seasons together
  # [2016, 2017, 2020, 2021] → [[2016, 2017], [2020, 2021]]
  def group_consecutive_seasons(seasons)
    return [] if seasons.blank?

    seasons.sort.chunk_while { |a, b| b - a == 1 }.to_a
  end

  def create_career_for_season_group(team, season_group)
    return if season_group.blank?

    first_season = season_group.min
    last_season = season_group.max

    # Start date is July 1 of first season (typical season start)
    start_date = Date.new(first_season, 7, 1)

    # End date depends on whether this is the current season
    active_seasons = fetch_active_seasons
    is_current = active_seasons.present? && last_season >= active_seasons.max

    end_date = if is_current
      nil # Still at club
    else
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

  def find_or_create_team(team_external_id:, team_name:)
    existing_team = FootballTeam.find_by(external_id: team_external_id)
    return existing_team if existing_team.present?

    team_profile = fetch_team_profile(team_id: team_external_id)
    return nil if team_profile.blank? || team_profile[0].nil? || team_profile[0][:team].nil?

    team_data = team_profile[0][:team]
    UpsertTeam.call(
      external_id: team_external_id,
      name: team_data[:name],
      code: team_data[:code],
      country: country(name: team_data[:country])
    )
  end

  def fetch_active_seasons
    FootballClient.call(end_point: "players/seasons?player=#{@player.external_id}")
  end

  def format_transfers(transfers)
    fmt_transfers = []
    transfers.each_with_index do |transfer, index|
      destination_team = transfer[:teams][:in]
      next if destination_team.nil?
      next unless senior_team?(destination_team[:name])

      start_date = fmt_date(transfer[:date])
      end_date = if index == transfers.length - 1
        latest_career_end_date
      else
        fmt_date(transfers[index + 1][:date])
      end

      next if end_date && start_date && end_date < start_date

      fmt_transfers << destination_team.merge(
        start_date: start_date,
        end_date: end_date
      )
    end
    fmt_transfers
  end

  def merge_consecutive_careers(transfers)
    return [] if transfers.empty?
    merged = []

    # Sort all transfers by start_date first to process chronologically
    sorted_transfers = transfers.sort_by { |t| t[:start_date] }

    # Track which transfers have been processed
    processed = Array.new(sorted_transfers.length, false)

    sorted_transfers.each_with_index do |transfer, i|
      next if processed[i]

      current = transfer.dup
      processed[i] = true

      # Look for consecutive transfers to the same team (no gap)
      sorted_transfers.each_with_index do |next_transfer, j|
        next if j <= i || processed[j]
        next if next_transfer[:id] != current[:id]

        current_end = current[:end_date]
        next_start = next_transfer[:start_date]

        # Only merge if they are truly consecutive (same end/start date or 1 day gap)
        # This means the player stayed at the club without going elsewhere
        if current_end && next_start && (next_start - current_end).abs <= 1
          # Extend the current career
          current[:end_date] = next_transfer[:end_date]
          processed[j] = true
        end
      end

      merged << current
    end

    merged.sort_by { |t| t[:start_date] }
  end

  def latest_career_end_date
    active_seasons = fetch_active_seasons
    return nil if active_seasons.blank?

    if Time.zone.now.year >= active_seasons.last
      nil
    else
      Date.new(active_seasons.last, 12, 31)
    end
  end

  def country(name:)
    Country.find_or_create_by!(name: name)
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

class UpsertPlayerCareer < ApplicationService
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

    # Identify first and last team from /players/teams endpoint
    # API returns "seasons" as an array, use min/max to find first/last
    sorted_career_teams = career_teams.sort_by { |t| t[:seasons]&.min || t[:season] || 0 }
    first_team_data = sorted_career_teams.first
    last_team_data = sorted_career_teams.last

    # Add first team (youth/academy) if not in transfers
    add_first_team(first_team_data, sorted_transfers) if first_team_data

    # Add last/current team if not in transfers
    add_last_team(last_team_data, sorted_transfers) if last_team_data && last_team_data != first_team_data

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

        # Check if creating this career would overlap with ANY existing career
        # This can happen due to data inconsistencies from the API
        overlaps_with_any = @player.careers.any? { |c| careers_overlap?(c.duration, new_duration) }
        next if overlaps_with_any

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

  def add_first_team(first_team_data, sorted_transfers)
    first_team_api_id = first_team_data.dig(:team, :id)
    return unless first_team_api_id

    # Check if this team already exists in transfers
    transfer_team_ids = sorted_transfers.map { |t| t.dig(:teams, :in, :id) }.compact
    return if transfer_team_ids.include?(first_team_api_id)

    team = find_or_create_team(
      team_external_id: first_team_api_id,
      team_name: first_team_data.dig(:team, :name)
    )
    return unless team

    # End date is the first transfer date (when player left)
    first_transfer_date = sorted_transfers.first ? fmt_date(sorted_transfers.first[:date]) : nil
    first_season = first_team_data[:seasons]&.min || first_team_data[:season]
    return unless first_season.is_a?(Integer)
    start_date = Date.new(first_season, 7, 1)

    return if @player.careers.exists?(football_team_id: team.id)

    @player.careers.create!(
      football_team_id: team.id,
      duration: start_date..first_transfer_date
    )
  end

  def add_last_team(last_team_data, sorted_transfers)
    last_team_api_id = last_team_data.dig(:team, :id)
    return unless last_team_api_id

    # Check if this team already exists in transfers
    transfer_team_ids = sorted_transfers.map { |t| t.dig(:teams, :in, :id) }.compact
    return if transfer_team_ids.include?(last_team_api_id)

    team = find_or_create_team(
      team_external_id: last_team_api_id,
      team_name: last_team_data.dig(:team, :name)
    )
    return unless team

    # Start from last transfer date or season start, no end date (still at club)
    last_transfer_date = sorted_transfers.last ? fmt_date(sorted_transfers.last[:date]) : nil
    last_season = last_team_data[:seasons]&.min || last_team_data[:season]
    start_date = if last_transfer_date
      last_transfer_date
    elsif last_season.is_a?(Integer)
      Date.new(last_season, 7, 1)
    else
      return
    end

    return if @player.careers.exists?(football_team_id: team.id)

    @player.careers.create!(
      football_team_id: team.id,
      duration: start_date..nil
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

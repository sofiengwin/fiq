class UpsertPlayerCareer < ApplicationService
  def initialize(player:, team: nil)
    @player = player
    @team = team # Optional: kept for backward compatibility but not used in API call
  end

  def call
    player_career = fetch_player_transfers

    # Handle empty response
    return if player_career.blank? || player_career[0].nil?

    transfers = player_career[0][:transfers]
    return if transfers.blank?

    # Sort transfers by date (oldest first) to ensure correct chronological order
    sorted_transfers = transfers.sort_by { |t| t[:date] }

    fmt_transfers = format_transfers(sorted_transfers)

    # Merge consecutive periods at the same club (Recommendation #1)
    merged_transfers = merge_consecutive_careers(fmt_transfers)

    # Delete existing careers to avoid duplicates (Recommendation #2)
    @player.careers.destroy_all

    # Create new career records with validation (Recommendation #3)
    merged_transfers.each do |transfer|
      team = find_or_create_team(team_external_id: transfer[:id], team_name: transfer[:name])
      next if team.nil?
      next if transfer[:start_date].nil? # Skip entries without start date

      Rails.logger.info "Creating career: #{transfer[:name]} from #{transfer[:start_date]} to #{transfer[:end_date]}"

      # Validate no overlapping careers before creating
      if has_overlapping_career?(transfer[:start_date], transfer[:end_date])
        Rails.logger.warn "Skipping overlapping career: #{transfer[:name]} (#{transfer[:start_date]} to #{transfer[:end_date]})"
        next
      end

      @player.careers.create!(team_id: team.id, duration: transfer[:start_date]..transfer[:end_date])
    end
  end

  private

  def fetch_player_transfers
    # Get ALL transfers for the player (no team filter)
    FootballClient.call(end_point: "transfers?player=#{@player.external_id}")
  end

  def fetch_team_profile(team_id:)
    FootballClient.call(end_point: "teams?id=#{team_id}")
  end

  def find_or_create_team(team_external_id:, team_name:)
    # First try to find existing team
    existing_team = Team.find_by(external_id: team_external_id)
    return existing_team if existing_team.present?

    # If not found, fetch full team profile from API
    team_profile = fetch_team_profile(team_id: team_external_id)[0]
    return nil if team_profile.nil? || team_profile[:team].nil?

    UpsertTeam.call(
      external_id: team_external_id,
      name: team_profile[:team][:name],
      code: team_profile[:team][:code],
      country: country(name: team_profile[:team][:country])
    )
  end

  def fetch_active_seasons
    FootballClient.call(end_point: "players/seasons?player=#{@player.external_id}")
  end

  def format_transfers(transfers)
    fmt_transfers = []

    # Transfers are ordered chronologically (oldest first)
    # For each transfer, calculate the career period at that club
    transfers.each_with_index do |transfer, index|
      # Extract the destination team (where player transferred TO)
      destination_team = transfer[:teams][:in]
      next if destination_team.nil?

      # Start date: when player joined this club
      start_date = fmt_date(transfer[:date])

      # End date: when player left (= date of next transfer, or nil if still active)
      end_date = if index == transfers.length - 1
        # This is the last (most recent) transfer - player might still be at this club
        latest_career_end_date
      else
        # Player left when they made the next transfer
        fmt_date(transfers[index + 1][:date])
      end

      # Skip if dates are invalid (end before start)
      next if end_date && start_date && end_date < start_date

      fmt_transfers << destination_team.merge(
        start_date: start_date,
        end_date: end_date
      )
    end

    fmt_transfers
  end

  # Merge consecutive periods at the same club (e.g., loan returns, re-signings)
  def merge_consecutive_careers(transfers)
    return [] if transfers.empty?

    merged = []

    # Group by team ID and merge overlapping/adjacent periods
    transfers.group_by { |t| t[:id] }.each do |team_id, team_transfers|
      # Sort by start date
      sorted = team_transfers.sort_by { |t| t[:start_date] }

      current = sorted.first.dup

      sorted[1..].each do |transfer|
        current_end = current[:end_date] || Date::Infinity.new
        transfer_start = transfer[:start_date]

        # Merge if periods are adjacent or overlapping (within 1 day tolerance)
        if transfer_start <= current_end + 1.day
          # Extend the period
          current[:end_date] = transfer[:end_date] if transfer[:end_date].nil? ||
            (current[:end_date] && transfer[:end_date] && transfer[:end_date] > current[:end_date])
        else
          # Gap between periods - keep as separate stints
          merged << current
          current = transfer.dup
        end
      end

      merged << current
    end

    # Sort by start date to maintain chronological order
    merged.sort_by { |t| t[:start_date] }
  end  # Check if a career period would overlap with existing careers
  def has_overlapping_career?(start_date, end_date)
    @player.careers.any? do |career|
      career_start = career.duration.begin
      career_end = career.duration.end

      # Check for overlap
      # Careers overlap if: start1 < end2 AND start2 < end1
      (start_date < (career_end || Date::Infinity.new)) &&
        ((end_date || Date::Infinity.new) > career_start)
    end
  end

  def latest_career_end_date
    active_seasons = fetch_active_seasons
    pp active_seasons
    if Time.zone.now.year >= active_seasons.last
      nil
    else
      Date.new(active_seasons.last, 12, 31)
    end
  end

  def country(name:)
    Country.find_or_create_by!(name: name)
  end

  def fmt_date(date)
    return nil if date.nil?

    date.to_date
  end
end

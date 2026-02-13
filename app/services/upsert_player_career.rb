class UpsertPlayerCareer < ApplicationService
  def initialize(player:, team: nil)
    @player = player
    @team = team
  end

  def call
    player_career = fetch_player_transfers
    return if player_career.blank? || player_career[0].nil?

    transfers = player_career[0][:transfers]
    return if transfers.blank?

    sorted_transfers = transfers.sort_by { |t| t[:date] }
    fmt_transfers = format_transfers(sorted_transfers)
    merged_transfers = merge_consecutive_careers(fmt_transfers)

    # Clear existing careers
    @player.careers.destroy_all

    merged_transfers.each do |transfer|
      team = find_or_create_team(
        team_external_id: transfer[:id],
        team_name: transfer[:name]
      )
      next if team.nil? || transfer[:start_date].nil?

      @player.careers.create!(
        football_team_id: team.id,
        duration: transfer[:start_date]..transfer[:end_date]
      )
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

  def fetch_team_profile(team_id:)
    FootballClient.call(end_point: "teams?id=#{team_id}")
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

    transfers.group_by { |t| t[:id] }.each do |_team_id, team_transfers|
      sorted = team_transfers.sort_by { |t| t[:start_date] }
      current = sorted.first.dup

      sorted[1..].each do |transfer|
        current_end = current[:end_date] || Date::Infinity.new
        transfer_start = transfer[:start_date]

        if transfer_start <= current_end + 1.day
          current[:end_date] = transfer[:end_date] if transfer[:end_date].nil? ||
            (current[:end_date] && transfer[:end_date] && transfer[:end_date] > current[:end_date])
        else
          merged << current
          current = transfer.dup
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

  def fmt_date(date)
    date&.to_date
  rescue ArgumentError
    nil
  end
end

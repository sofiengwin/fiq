# frozen_string_literal: true

class BravePlayerCareer < ApplicationService
  CAREER_QUERY_TEMPLATE = <<~PROMPT
    Provide the senior career journey of footballer "%<player_name>s" avoid overlapping periods returned the result in the following JSON format only, with no additional text:
    {
      "name": "full name of the footballer",
      "nationality": "country",
      "position": "playing position",
      "senior_clubs": [
        {
          "club": "club name",
          "start_year": "day/month/year joined",
          "end_year": "day/month/year left or 'present' if still there"
        }
      ]
    }
    Include all senior clubs in chronological order.
  PROMPT

  def initialize(player:)
    @player = player
  end

  def call
    career_data = fetch_career_from_brave
    return if career_data.blank? || career_data[:error].present?

    process_career_data(career_data)
    @player.careers.reload
  rescue StandardError => e
    Rails.logger.error("BravePlayerCareer failed for player #{@player.id}: #{e.message}")
    raise e
  end

  private

  def fetch_career_from_brave
    query = format(CAREER_QUERY_TEMPLATE, player_name: @player.name)
    BraveSearchClient.call(query: query)
  end

  def process_career_data(data)
    senior_clubs = data[:senior_clubs]
    return if senior_clubs.blank?

    senior_clubs.each do |club_data|
      process_club_career(club_data)
    end
  end

  def process_club_career(club_data)
    club_name = club_data[:club]
    return if club_name.blank?

    team = find_or_create_team(club_name)
    return unless team

    start_date = parse_date(club_data[:start_year])
    end_date = parse_date(club_data[:end_year])

    return if start_date.nil?

    new_duration = start_date..end_date

    # Check for existing overlapping career at the same team
    existing_career = @player.careers
      .where(football_team_id: team.id)
      .find { |c| careers_overlap?(c.duration, new_duration) }

    if existing_career
      # Extend duration if brave data provides more info
      merged_start = [ existing_career.duration.begin, start_date ].compact.min
      merged_end = merge_end_dates(existing_career.duration.end, end_date)
      existing_career.update!(duration: merged_start..merged_end)
    else
      # Skip if exact career already exists
      return if @player.careers.exists?(football_team_id: team.id, duration: new_duration)

      @player.careers.create!(
        football_team_id: team.id,
        duration: new_duration
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("BravePlayerCareer: Skipping invalid career for #{@player.name} at #{club_data[:club]}: #{e.message}")
  end

  def find_or_create_team(club_name)
    # Try to find by name (case-insensitive)
    team = FootballTeam.where("LOWER(name) = ?", club_name.downcase).first
    return team if team

    # Try fuzzy match for common variations
    team = FootballTeam.where("LOWER(name) LIKE ?", "%#{club_name.downcase}%").first
    return team if team

    # Create new team without external_id (brave data doesn't include it)
    country = Country.find_or_create_by!(name: "Unknown")
    FootballTeam.create!(
      name: club_name,
      country: country
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("BravePlayerCareer: Could not create team '#{club_name}': #{e.message}")
    nil
  end

  def parse_date(date_str)
    return nil if date_str.blank?
    return nil if date_str.to_s.downcase == "present"

    # Handle various date formats
    date_str = date_str.to_s.strip

    # Try parsing "day/month/year" format first
    if date_str.match?(%r{\d{1,2}/\d{1,2}/\d{4}})
      Date.strptime(date_str, "%d/%m/%Y")
    # Try "month/year" format
    elsif date_str.match?(%r{\d{1,2}/\d{4}})
      Date.strptime("01/#{date_str}", "%d/%m/%Y")
    # Try just year
    elsif date_str.match?(/^\d{4}$/)
      Date.new(date_str.to_i, 7, 1) # Default to July 1st (typical season start)
    else
      Date.parse(date_str)
    end
  rescue ArgumentError, Date::Error => e
    Rails.logger.warn("BravePlayerCareer: Could not parse date '#{date_str}': #{e.message}")
    nil
  end

  def merge_end_dates(date1, date2)
    return nil if date1.nil? && date2.nil?
    return date1 if date2.nil?
    return date2 if date1.nil?
    [ date1, date2 ].max
  end

  def careers_overlap?(range1, range2)
    return false if range1.nil? || range2.nil?

    start1 = range1.begin
    end1 = range1.end || Date.new(9999, 12, 31)
    start2 = range2.begin
    end2 = range2.end || Date.new(9999, 12, 31)

    return false if start1.nil? || start2.nil?

    start1 <= end2 && start2 <= end1
  end
end

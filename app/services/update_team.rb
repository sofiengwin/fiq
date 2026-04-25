# frozen_string_literal: true

# Service to update a football team from the API
#
# Usage:
#   UpdateTeam.call(football_team: team)
#
class UpdateTeam < ApplicationService
  class TeamNotFoundError < StandardError; end

  def initialize(football_team:)
    @football_team = football_team
  end

  def call
    raise ArgumentError, "football_team must have an external_id" if @football_team.external_id.blank?

    team_data = fetch_team_data
    raise TeamNotFoundError, "Team not found for external_id: #{@football_team.external_id}" if team_data.blank?

    update_team(team_data)
  end

  private

  def fetch_team_data
    response = FootballClient.call(end_point: "teams?id=#{@football_team.external_id}")
    response&.first
  end

  def update_team(data)
    team_info = data[:team]
    country = find_or_create_country(team_info[:country])

    @football_team.update!(
      name: team_info[:name],
      code: team_info[:code],
      country: country,
      national: team_info[:national] || false
    )

    @football_team
  end

  def find_or_create_country(country_name)
    return nil if country_name.blank?

    Country.find_or_create_by!(name: country_name)
  end
end

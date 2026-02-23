class UpsertLeagueTeams < ApplicationService
  def initialize(league_id:, season:, competition_name:)
    @league_id = league_id
    @season = season
    @competition_name = competition_name
  end

  def call
    result = fetch_teams
    result.map do |team|
      UpsertTeam.call(
        external_id: team[:team][:id],
        name: team[:team][:name],
        code: team[:team][:code],
        country: country(name: team[:team][:country]),
        competition: competition
      )
    end
  end

  private

  def fetch_teams
    FootballClient.call(end_point: "teams?league=#{@league_id}&season=#{@season}")
  end

  def country(name:)
    @country ||= Country.find_or_create_by!(name: name)
  end

  def competition
    return nil if @league_id.blank?
    Competition.find_or_create_by!(external_id: @league_id) do |c|
      c.name = @competition_name
      c.country_id = @country.id
    end
  end
end

# UpsertLeagueTeams.call(league_id: 39, season: 2023, competition_name: "Premier League")

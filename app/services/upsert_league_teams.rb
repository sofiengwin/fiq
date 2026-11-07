class UpsertLeagueTeams < ApplicationService
  def initialize(league_id:, season:, competition_name:)
    @league_id = league_id
    @season = season
    @competition_name = competition_name
  end

  # L8: auto-path league fan-out — the single teams fetch spends one
  # auto-budget request. Over budget the league stays pending with zero
  # HTTP. The competition row is recorded but never auto-backfilled here
  # (backfill stays an operator-run Pl39Backfill invocation); the probe owns
  # allowlist gating for that path.
  def call
    result = fetch_teams
    result.map do |team|
      UpsertTeam.call(
        external_id: team[:team][:id],
        name: team[:team][:name],
        code: team[:team][:code],
        country: country(name: team[:team][:country]),
        national: team[:team][:national] || false,
        competition: competition
      )
    end
  rescue AutoDiscovery::OverBudget => e
    AutoDiscovery.note("pending-budget", kind: "league", league_id: @league_id, season: @season, reason: e.message)
    []
  end

  private

  def fetch_teams
    AutoDiscovery.checkout!
    FootballClient.call(end_point: "teams?league=#{@league_id}&season=#{@season}")
  end

  def country(name:)
    @country ||= CountryAlias.find_or_create!(name)
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
#
#
# 500.times do |i|
#   FootballClient.call(end_point: "teams?league=#{39}&season=#{2023}")
# end

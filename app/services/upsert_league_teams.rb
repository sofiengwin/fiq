class UpsertLeagueTeams < ApplicationService
  def initialize(name:, code:, country_id:, national:, external_id:, logo_url:)
    @name = name
    @code = code
    @country_id = country_id
    @national = national
    @external_id = external_id
  end

  def call
    Team.find_or_create_by!(external_id: @external_id) do |league_team|
      league_team.name = @name
      league_team.code = @code
      league_team.country_id = @country_id
      league_team.national = @national
    end
  end
end

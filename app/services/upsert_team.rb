class UpsertTeam < ApplicationService
  def initialize(external_id:, name:, code:, country:, competition: nil)
    @external_id = external_id
    @name = name
    @code = code
    @country = country
    @competition = competition
  end

    def call
      team = Team.find_or_create_by!(external_id: @external_id) do |team|
        team.name = @name
        team.code = @code
        team.country_id = @country.id
      end

      if @competition
        team.competitions << @competition
      end

      team
    end
end

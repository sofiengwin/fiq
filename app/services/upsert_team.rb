class UpsertTeam < ApplicationService
  def initialize(external_id:, name:, code:, country:, competition: nil)
    @external_id = external_id
    @name = name
    @code = code
    @country = country
    @competition = competition
  end

  def call
    team = FootballTeam.find_or_create_by!(external_id: @external_id) do |t|
      t.name = @name
      t.code = @code
      t.national = @national
      t.country_id = @country.id
    end

    if @competition && !team.competitions.include?(@competition)
      team.competitions << @competition
    end

    team
  end
end

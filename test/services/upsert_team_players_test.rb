require "test_helper"

class UpsertTeamPlayersTest < ActiveSupport::TestCase
  test "upsert player" do
    VCR.use_cassette("player/squads") do
      team = teams(:one)
      team.update(external_id: 33, name: "Manchester United", code: "MUN")
      players = UpsertTeamPlayers.call(team: team)

      assert players.map(&:name).include?("Bruno Fernandes")
    end
  end
end

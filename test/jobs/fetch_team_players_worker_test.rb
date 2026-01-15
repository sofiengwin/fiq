require "test_helper"

class FetchTeamPlayersWorkerTest < ActiveSupport::TestCase
  test "#perform" do
    VCR.use_cassette("players/squads") do
      team = teams(:one)
      team.update(external_id: 33)

      FetchTeamPlayersWorker.new.perform(team.id)

      manu_top = [ "Bruno Fernandes", "Casemiro", "M. Ugarte", "B. Mbeumo" ]
      assert_equal (team.players.map(&:name) & manu_top).size, manu_top.size
    end
  end
end

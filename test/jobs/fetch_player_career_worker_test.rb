require "test_helper"

class FetchPlayerCareerWorkerTest < ActiveSupport::TestCase
  test "#perform" do
    VCR.use_cassette("player/transfer") do
      VCR.use_cassette("team/profile") do
        VCR.use_cassette("players/seasons") do
          player = players(:one)
          player.careers.destroy_all
          player.update(external_id: 886)
          
          # Team ID parameter is now optional
          FetchPlayerCareerWorker.new.perform(player.id)

          assert_equal player.careers.reload.map { |career| [ career.team.name, career.duration.to_s ] }, [ [ "Manchester United", "2021-07-01..Infinity" ], [ "AC Milan", "2020-10-04...2021-07-02" ], [ "Manchester United", "2018-06-08...2020-10-05" ] ]
        end
      end
    end
  end
end

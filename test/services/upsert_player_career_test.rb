require "test_helper"

class UpsertPlayerCareerTest < ActiveSupport::TestCase
  test "upsert player career" do
    VCR.use_cassette("player/transfer") do
      VCR.use_cassette("team/profile") do
        VCR.use_cassette("players/seasons") do
          player = players(:one)
          player.careers.destroy_all
          player.update(external_id: 886)
          
          # Team parameter no longer required - service fetches all transfers
          UpsertPlayerCareer.call(player: player)

          assert_equal player.careers.reload.map { |career| [ career.team.name, career.duration.to_s ] }, [ [ "Manchester United", "2021-07-01..Infinity" ], [ "AC Milan", "2020-10-04...2021-07-02" ], [ "Manchester United", "2018-06-08...2020-10-05" ] ]
        end
      end
    end
  end
  
  test "upsert player career with loan" do
    VCR.use_cassette("player/transfer-arsenal") do
      VCR.use_cassette("team/profile-arsenal") do
        VCR.use_cassette("players/seasons-arsenal") do
          player = players(:one)
          player.careers.destroy_all
          player.update(external_id: 19465)
          
          # Team parameter no longer required - service fetches all transfers
          UpsertPlayerCareer.call(player: player)

          assert_equal player.careers.reload.map { |career| [ career.team.name, career.duration.to_s ] }, [ [ "Arsenal", "2021-07-01..Infinity" ], [ "AC Milan", "2020-10-04...2021-07-02" ], [ "Manchester United", "2018-06-08...2020-10-05" ] ]
        end
      end
    end
  end
end

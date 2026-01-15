require "test_helper"

class UpsertTeamTest < ActiveSupport::TestCase
  test "upsert team - without league" do
    team = UpsertTeam.call(
      external_id: 33,
      name: "Manchester United",
      code: "MUN",
      country: countries(:one),
    )

    team = Team.last

    assert_equal "Manchester United", team.reload.name
    assert_equal team.competitions.map(&:name), []
    assert_equal team.country.name, "England"
  end
  test "upsert team - with league" do
    team = UpsertTeam.call(
      external_id: 33,
      name: "Manchester United",
      code: "MUN",
      country: countries(:one),
      competition: competitions(:one),
    )

    team = Team.last

    assert_equal "Manchester United", team.reload.name
    assert_equal team.competitions.map(&:name), [ competitions(:one).name ]
    assert_equal team.country.name, "England"
  end
end

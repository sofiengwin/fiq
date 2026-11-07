require "test_helper"

class UpsertTeamTest < ActiveSupport::TestCase
  setup do
    @country = Country.find_or_create_by!(name: "England")
  end

  test "creates team without national defaults to false" do
    team = UpsertTeam.call(
      external_id: "900001",
      name: "Test Club",
      code: "TST",
      country: @country
    )

    assert team.persisted?
    assert_equal false, team.national
  end

  test "nil national maps to false" do
    team = UpsertTeam.call(
      external_id: "900002",
      name: "Nil National Club",
      code: "NIL",
      country: @country,
      national: nil
    )

    assert team.persisted?
    assert_equal false, team.reload.national
  end

  test "true national is preserved" do
    team = UpsertTeam.call(
      external_id: "900003",
      name: "National Side",
      code: "NAT",
      country: @country,
      national: true
    )

    assert team.persisted?
    assert_equal true, team.reload.national
  end
end

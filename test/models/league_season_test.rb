require "test_helper"

# LeagueSeason memo: write/read of the DB-backed league scope, TTL expiry,
# and convention-range validation. No minutes_played, no other tables.
class LeagueSeasonTest < ActiveSupport::TestCase
  test "record_contact! writes a memo row on every contact" do
    row = LeagueSeason.record_contact!(
      league_id: 39, season: 2022, status: "ok", team_count: 20
    )

    assert_equal 39, row.league_id
    assert_equal 2022, row.season
    assert_equal "ok", row.status
    assert_equal 20, row.team_count
    assert_not_nil row.checked_at

    assert_equal row.id, LeagueSeason.memo_for(39, 2022).id
  end

  test "record_contact! refreshes the existing memo instead of duplicating" do
    first = LeagueSeason.record_contact!(
      league_id: 39, season: 2022, status: "ok", team_count: 20
    )
    second = LeagueSeason.record_contact!(
      league_id: 39, season: 2022, status: "dead",
      team_count: 0, reason: "empty teams response"
    )

    assert_equal first.id, second.id
    assert_equal 1, LeagueSeason.where(league_id: 39, season: 2022).count
    assert_equal "dead", second.status
    assert_equal "empty teams response", second.reason
  end

  test "ok seasons and dead entries read back per league" do
    LeagueSeason.record_contact!(league_id: 135, season: 2022, status: "ok", team_count: 20)
    LeagueSeason.record_contact!(
      league_id: 135, season: 2021, status: "dead",
      team_count: 0, reason: "empty teams response"
    )

    assert_equal [ 2022 ], LeagueSeason.ok_seasons_for(135, present_year: 2023)
    assert_equal(
      [ { season: 2021, reason: "empty teams response" } ],
      LeagueSeason.dead_entries_for(135)
    )
    assert_empty LeagueSeason.ok_seasons_for(999, present_year: 2023)
  end

  test "ok seasons never list seasons past the present year" do
    LeagueSeason.record_contact!(league_id: 39, season: 2050, status: "ok", team_count: 20)

    assert_empty LeagueSeason.ok_seasons_for(39, present_year: 2023)
  end

  test "dead memo is fresh inside the 30d TTL and due for recheck after expiry" do
    row = LeagueSeason.record_contact!(
      league_id: 39, season: 2008, status: "dead",
      team_count: 0, reason: "empty teams response"
    )

    assert row.fresh?
    assert_not row.recheck_due?

    travel_to(31.days.from_now) do
      assert_not row.reload.fresh?
      assert row.reload.recheck_due?
    end
  end

  test "convention range is 2010 through the present year" do
    assert LeagueSeason.in_convention_range?(2010, 2023)
    assert LeagueSeason.in_convention_range?(2023, 2023)
    assert_not LeagueSeason.in_convention_range?(2009, 2023)
    assert_not LeagueSeason.in_convention_range?(2024, 2023)
  end
end

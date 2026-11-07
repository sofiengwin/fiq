require "test_helper"
require "tmpdir"

# L6 — Nightly stale-only refresh, live-only (Pl39NightlyRefresh).
# Live-only: every stale row costs one live request against the 200 cap;
# dry-run performs zero HTTP; reruns re-walk live (0 live only when nothing
# is stale). Derived from tickets.md T7 "Done when" (not from implementation):
#   - recurring.yml contains the 02:00 UTC team_sync entry (pinned in
#     DataNightlyRefreshRakeTest alongside the rake dry-run);
#   - dry-run on a DB with 3 stale + 2 fresh rows reports exactly the 3
#     stale and enqueues/calls nothing;
#   - live run with stubbed client refreshes only stale rows, updates their
#     last_refreshed_at, respects the 200 cap, and leaves fresh rows
#     untouched.
class Pl39NightlyRefreshTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.reset!
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(
      FootballClient::THROTTLE_ENV_VAR
    )
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    @country = Country.find_or_create_by!(name: "T7 Testland")
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
  end

  test "dry-run reports exactly the stale rows and performs zero HTTP, zero writes, zero enqueues" do
    stale_nil_team = make_team(701, nil)
    stale_old_team = make_team(702, 31.days.ago)
    stale_player = make_player(701, nil)
    make_team(703, 1.day.ago)
    make_player(702, Time.current)

    result = nil
    assert_no_enqueued_jobs do
      result = Pl39NightlyRefresh.call(dry_run: true)
    end

    assert_equal :completed, result[:status]
    assert_equal true, result[:dry_run]
    assert_equal 2, result[:teams]
    assert_equal 1, result[:players]
    assert_equal 0, result[:careers]
    assert_equal 3, result[:total]
    assert_equal 0, result[:live_requests]
    assert_equal false, result[:capped]
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)

    # Zero writes: stale rows are still stale.
    assert_nil stale_nil_team.reload.last_refreshed_at
    assert_nil stale_player.reload.last_refreshed_at
    assert_in_delta 31.days.ago.to_f, stale_old_team.reload.last_refreshed_at.to_f, 5
  end

  test "live run refreshes only stale rows and leaves fresh rows untouched" do
    stub_all_empty
    stale_team = make_team(711, nil)
    old_team = make_team(712, 45.days.ago)
    fresh_team = make_team(713, 1.day.ago)
    fresh_before = fresh_team.last_refreshed_at
    stale_player = make_player(711, 60.days.ago)
    fresh_player = make_player(712, Time.current)
    fresh_player_before = fresh_player.last_refreshed_at
    stale_career = make_career(stale_player, stale_team, nil)

    result = Pl39NightlyRefresh.call(dry_run: false)

    assert_equal :completed, result[:status]
    assert_equal 2, result[:teams]
    assert_equal 1, result[:players]
    assert_equal 1, result[:careers]
    assert_equal 4, result[:total]
    assert_equal 4, result[:live_requests]
    assert_equal false, result[:capped]

    assert_not_nil stale_team.reload.last_refreshed_at
    assert_not_nil old_team.reload.last_refreshed_at
    assert_not_nil stale_player.reload.last_refreshed_at
    assert_not_nil stale_career.reload.last_refreshed_at
    assert_in_delta fresh_before.to_f, fresh_team.reload.last_refreshed_at.to_f, 1
    assert_in_delta fresh_player_before.to_f, fresh_player.reload.last_refreshed_at.to_f, 1
  end

  test "low-cap run stops cleanly at the cap and resumes on the next invocation" do
    stub_all_empty
    teams = (721..724).map { |ext| make_team(ext, nil) }

    capped = Pl39NightlyRefresh.call(dry_run: false, max_requests: 2)

    assert_equal :completed, capped[:status]
    assert capped[:capped]
    assert_equal 2, capped[:live_requests]
    assert_equal 2, capped[:teams]
    assert_equal 2, teams.count { |team| team.reload.last_refreshed_at.present? }
    assert_requested(:get, /v3\.football\.api-sports\.io/, times: 2)

    resumed = Pl39NightlyRefresh.call(dry_run: false, max_requests: 2)

    assert_equal :completed, resumed[:status]
    assert_not resumed[:capped]
    assert_equal 2, resumed[:live_requests]
    assert teams.all? { |team| team.reload.last_refreshed_at.present? }
  end

  test "PL39-linked rows refresh first under a tight cap" do
    stub_all_empty
    competition = Competition.create!(external_id: "39", name: "Premier League", country: @country)
    pl_team = make_team(731, nil)
    pl_team.competitions << competition
    other_team = make_team(732, nil)

    result = Pl39NightlyRefresh.call(dry_run: false, max_requests: 1)

    assert result[:capped]
    assert_equal 1, result[:live_requests]
    assert_not_nil pl_team.reload.last_refreshed_at
    assert_nil other_team.reload.last_refreshed_at
  end

  test "exact 30-day boundary counts as stale, recent stays fresh" do
    stub_all_empty
    boundary = make_team(741, 30.days.ago)
    recent = make_team(742, 29.days.ago)

    result = Pl39NightlyRefresh.call(dry_run: true)

    assert_equal 1, result[:teams]
    assert_equal 1, result[:total]

    Pl39NightlyRefresh.call(dry_run: false)

    assert_not_nil boundary.reload.last_refreshed_at
    assert_in_delta 29.days.ago.to_f, recent.reload.last_refreshed_at.to_f, 60
  end

  test "rows without external ids are skipped without consuming budget" do
    stub_all_empty
    unlinked = FootballTeam.create!(name: "T7 No Ext", country: @country, last_refreshed_at: nil)
    assert_nil unlinked.external_id
    normal = make_team(751, nil)

    result = Pl39NightlyRefresh.call(dry_run: true)
    assert_equal 2, result[:teams]

    live = Pl39NightlyRefresh.call(dry_run: false)

    assert_equal 1, live[:teams]
    assert_equal 1, live[:skipped]
    assert_equal 1, live[:live_requests]
    assert_not live[:capped]
    assert_nil unlinked.reload.last_refreshed_at
    assert_not_nil normal.reload.last_refreshed_at
  end

  test "rerun after a refresh finds nothing stale and makes 0 live requests" do
    stub_all_empty
    make_team(761, nil)

    first = Pl39NightlyRefresh.call(dry_run: false)
    assert_equal 1, first[:live_requests]

    # Drop the stubs: any live HTTP from here on raises instead of succeeding.
    WebMock.reset!

    second = Pl39NightlyRefresh.call(dry_run: false)

    assert_equal :completed, second[:status]
    assert_equal 0, second[:live_requests]
    assert_not second[:capped]
  end

  private

  def make_team(external_id, refreshed_at)
    FootballTeam.create!(
      name: "T7 Team #{external_id}", external_id: external_id.to_s,
      country: @country, last_refreshed_at: refreshed_at
    )
  end

  def make_player(external_id, refreshed_at)
    Player.create!(
      name: "T7 Player #{external_id}", external_id: external_id.to_s,
      last_refreshed_at: refreshed_at
    )
  end

  def make_career(player, team, refreshed_at)
    Career.create!(
      player: player, football_team: team,
      duration: Date.new(2022, 7, 1)...Date.new(2023, 7, 1),
      goals: 2, last_refreshed_at: refreshed_at
    )
  end

  def stub_all_empty
    stub_request(:get, /v3\.football\.api-sports\.io/).to_return(
      status: 200, body: { response: [], errors: {} }.to_json
    )
  end
end

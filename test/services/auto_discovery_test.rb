require "test_helper"

# L8 — First-seen skeleton/enqueue + 5000/day auto budget + priority.
#
# Derived from the ticket (not from implementation):
#   - career-path new teams enqueue squad iff league in scope, else
#     pending-manual (skeleton kept, zero further HTTP);
#   - player first-seen enqueues a career fetch;
#   - the auto budget counter is separate from the batch (500) / nightly
#     (200) caps; over budget stays pending with zero HTTP;
#   - priority batch > nightly > auto.
class AutoDiscoveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebMock::API

  setup do
    WebMock.reset!
    AutoDiscovery.reset!
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    @country = Country.find_or_create_by!(name: "L8 Testland")
  end

  teardown do
    WebMock.reset!
    AutoDiscovery.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
  end

  test "auto scope is on for the top-five leagues and off for the rest" do
    [ 39, 61, 78, 135, 140 ].each do |league_id|
      assert AutoDiscovery.in_scope_league?(league_id), "league #{league_id} should be in scope"
    end

    [ 144, 94, 71, 0 ].each do |league_id|
      assert_not AutoDiscovery.in_scope_league?(league_id), "league #{league_id} should be out of scope"
    end

    assert AutoDiscovery.in_scope_league?("39")
  end

  test "auto budget is 5000 per day, separate from the batch and nightly caps" do
    assert_equal 5000, AutoDiscovery::DAILY_AUTO_BUDGET
    assert_equal 500, Pl39Backfill::DEFAULT_MAX_REQUESTS
    assert_equal 200, LeagueNightlyRefresh::DEFAULT_MAX_REQUESTS
  end

  test "checkout spends the daily counter and refuses past the cap" do
    assert_equal 0, AutoDiscovery.spent_today
    assert_equal 5000, AutoDiscovery.remaining_today
    assert_not AutoDiscovery.over_budget?

    assert AutoDiscovery.checkout(3)
    assert_equal 3, AutoDiscovery.spent_today
    assert_equal 4997, AutoDiscovery.remaining_today

    assert AutoDiscovery.checkout(4997)
    assert AutoDiscovery.over_budget?
    assert_not AutoDiscovery.checkout
    assert_raises(AutoDiscovery::OverBudget) { AutoDiscovery.checkout! }

    AutoDiscovery.reset!
    assert_equal 0, AutoDiscovery.spent_today
    assert_not AutoDiscovery.over_budget?
  end

  test "batch and nightly runs do not consume the auto budget" do
    stub_all_empty
    make_team(811, nil)
    make_player(811, nil)

    LeagueNightlyRefresh.call(dry_run: false)

    assert_equal 0, AutoDiscovery.spent_today
  end

  test "over-budget career path stays pending with zero HTTP" do
    AutoDiscovery.checkout(AutoDiscovery::DAILY_AUTO_BUDGET)
    player = make_player(821, nil)
    teams_before = FootballTeam.count

    result = nil
    assert_no_enqueued_jobs do
      result = UpsertPlayerCareer.call(player: player)
    end

    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
    assert_equal teams_before, FootballTeam.count
    assert_empty Array(result)
  end

  test "over-budget squad and league paths stay pending with zero HTTP" do
    AutoDiscovery.checkout(AutoDiscovery::DAILY_AUTO_BUDGET)
    team = make_team(822, nil)

    assert_equal [], UpsertTeamPlayers.call(team: team)
    assert_equal [], UpsertLeagueTeams.call(league_id: 39, season: 2023, competition_name: "Premier League")
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "career-path first-seen team in scope enqueues its squad" do
    stub_career_path(external_team_id: 831, country: "Italy")
    origin = make_team(830, Time.current)
    origin.competitions << Competition.create!(external_id: "39", name: "Premier League", country: @country)
    player = make_player(831, nil)

    UpsertPlayerCareer.call(player: player, team: origin)

    squad_team = FootballTeam.find_by!(external_id: "831")
    assert_equal "L8 FC 831", squad_team.name
    assert_equal "Italy", squad_team.country.name
    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ squad_team.id ])
    assert player.careers.where(football_team: squad_team).exists?
  end

  test "career-path first-seen team out of scope stays pending-manual with zero profile HTTP" do
    stub_career_path(external_team_id: 832, country: "Colombia")
    origin = make_team(830, Time.current)
    origin.competitions << Competition.create!(external_id: "144", name: "Jupiler Pro League", country: @country)
    player = make_player(832, nil)

    assert_no_enqueued_jobs do
      UpsertPlayerCareer.call(player: player, team: origin)
    end

    skeleton = FootballTeam.find_by!(external_id: "832")
    assert_equal "L8 FC 832", skeleton.name
    assert_not_requested(:get, %r{/teams\?id=832})
    # The career linkage is still built so coverage measures the gap.
    assert player.careers.where(football_team: skeleton).exists?
  end

  test "explicit league context overrides the originating team" do
    stub_career_path(external_team_id: 833, country: "Italy")
    player = make_player(833, nil)

    assert_no_enqueued_jobs do
      UpsertPlayerCareer.call(player: player, league_id: 144)
    end
    assert_not_requested(:get, %r{/teams\?id=833})
    assert FootballTeam.exists?(external_id: "833")

    FootballTeam.find_by!(external_id: "833").destroy!
    player.careers.destroy_all

    UpsertPlayerCareer.call(player: player, league_id: 39)
    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ FootballTeam.find_by!(external_id: "833").id ])
  end

  test "unknown league context preserves legacy fetch without enqueue" do
    stub_career_path(external_team_id: 834, country: "Italy")
    player = make_player(834, nil)

    assert_no_enqueued_jobs do
      UpsertPlayerCareer.call(player: player)
    end

    team = FootballTeam.find_by!(external_id: "834")
    assert_equal "Italy", team.country.name
    assert_requested(:get, %r{/teams\?id=834}, times: 1)
  end

  test "ambiguous team profile is dead with reason and builds no career" do
    stub_career_path(external_team_id: 835, country: "Italy", profile_teams: [])
    origin = make_team(830, Time.current)
    origin.competitions << Competition.create!(external_id: "39", name: "Premier League", country: @country)
    player = make_player(835, nil)

    assert_no_enqueued_jobs do
      UpsertPlayerCareer.call(player: player, team: origin)
    end

    assert_not FootballTeam.exists?(external_id: "835")
    assert_empty player.careers.reload
  end

  test "squad-path first-seen player enqueues its career fetch" do
    stub_request(:get, %r{/players/squads}).to_return(
      status: 200, body: { response: [ { players: [ { id: 841, name: "L8 Rookie", position: "Midfielder", age: 21 } ] } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/players/profiles}).to_return(
      status: 200, body: { response: [ { player: { id: 841, name: "L8 Rookie" } } ], errors: {} }.to_json
    )
    team = make_team(840, Time.current)

    # wait_time reads Solid Queue tables, which do not exist in the test DB;
    # the enqueue below is what this ticket pins, not the stagger.
    job = FetchTeamPlayersJob.new(team.id)
    job.define_singleton_method(:wait_time) { Time.current }
    job.perform_now

    rookie = Player.find_by!(external_id: "841")
    assert_equal "L8 Rookie", rookie.name
    assert_enqueued_with(job: FetchPlayerCareerJob, args: [ rookie.id, team.id ])
  end

  test "name-only teams never auto-fetch" do
    payload = {
      name: "L8 Star",
      senior_clubs: [ { club: "L8 Nowhere Rovers", start_year: "01/07/2020", end_year: "present" } ]
    }
    player = make_player(842, nil)

    original = BraveSearchClient.method(:call)
    BraveSearchClient.define_singleton_method(:call) { |*| payload }
    begin
      assert_no_enqueued_jobs do
        BravePlayerCareer.call(player: player)
      end
    ensure
      BraveSearchClient.define_singleton_method(:call, original)
    end

    bare = FootballTeam.find_by!(name: "L8 Nowhere Rovers")
    assert_nil bare.external_id
  end

  test "priority runs batch first, then nightly, then auto" do
    assert_equal 0, AutoDiscovery::BATCH_PRIORITY
    assert_equal 10, AutoDiscovery::NIGHTLY_PRIORITY
    assert_equal 50, AutoDiscovery::AUTO_PRIORITY

    assert_equal AutoDiscovery::NIGHTLY_PRIORITY, NightlyDataRefreshJob.priority
    assert_equal AutoDiscovery::AUTO_PRIORITY, FetchTeamPlayersJob.priority
    assert_equal AutoDiscovery::AUTO_PRIORITY, FetchPlayerCareerJob.priority
    assert_equal AutoDiscovery::AUTO_PRIORITY, LeagueTeamsJob.priority
  end

  private

  def make_team(external_id, refreshed_at)
    FootballTeam.create!(
      name: "L8 Team #{external_id}", external_id: external_id.to_s,
      country: @country, last_refreshed_at: refreshed_at
    )
  end

  def make_player(external_id, refreshed_at)
    Player.create!(
      name: "L8 Player #{external_id}", external_id: external_id.to_s,
      last_refreshed_at: refreshed_at
    )
  end

  def stub_all_empty
    stub_request(:get, /v3\.football\.api-sports\.io/).to_return(
      status: 200, body: { response: [], errors: {} }.to_json
    )
  end

  def stub_career_path(external_team_id:, country:, profile_teams: nil)
    profile = profile_teams || [ { team: { id: external_team_id, name: "L8 FC #{external_team_id}", code: "L8F", country: country, national: false } } ]
    stub_request(:get, %r{/players/teams}).to_return(
      status: 200,
      body: { response: [ { team: { id: external_team_id, name: "L8 FC #{external_team_id}" }, seasons: [ 2023 ] } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/transfers}).to_return(
      status: 200, body: { response: [ { transfers: [] } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/players/seasons}).to_return(
      status: 200, body: { response: [ 2023 ], errors: {} }.to_json
    )
    stub_request(:get, %r{/teams\?id=#{external_team_id}}).to_return(
      status: 200, body: { response: profile, errors: {} }.to_json
    )
  end
end

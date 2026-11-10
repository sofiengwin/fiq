require "test_helper"

# L8 — First-seen full create/enqueue (gateless) + quota-exhaustion retry-next-day + priority.
#
# Derived from the ticket (not from implementation):
#   - career-path new teams always get a full create + squad enqueue
#     (all leagues treated in-scope);
#   - player first-seen enqueues a career fetch;
#   - there is no daily auto counter: quota exhaustion
#     (FootballClientRateLimitExceeded) propagates out of the auto upserts
#     instead of being swallowed, Solid Queue retry_on backs the job off,
#     and failed rows keep their stale last_refreshed_at so the next
#     nightly (02:00 UTC) retries them — that is the "retry next day"
#     mechanism;
#   - priority batch > nightly > auto.
class AutoDiscoveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebMock::API

  setup do
    WebMock.reset!
    AutoDiscovery.clear_dead("team:835")
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    @country = Country.find_or_create_by!(name: "L8 Testland")
  end

  teardown do
    WebMock.reset!
    AutoDiscovery.clear_dead("team:835")
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
  end

  test "auto scope is gateless: every league is treated in-scope" do
    [ 39, 61, 78, 135, 140, 144, 94, 71, 0 ].each do |league_id|
      assert AutoDiscovery.in_scope_league?(league_id), "league #{league_id} should be in scope"
    end

    assert AutoDiscovery.in_scope_league?("39")
    assert AutoDiscovery.in_scope_league?("144")
  end

  test "quota exhaustion propagates from the career path instead of being swallowed" do
    stub_rate_limited
    player = make_player(851, nil)

    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      UpsertPlayerCareer.call(player: player)
    end
  end

  test "quota exhaustion propagates from the squad and league paths" do
    stub_rate_limited
    team = make_team(852, nil)

    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      UpsertTeamPlayers.call(team: team)
    end
    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      UpsertLeagueTeams.call(league_id: 39, season: 2023, competition_name: "Premier League")
    end
  end

  test "quota-exhausted rows stay stale with no dead mark so the next nightly retries them" do
    stub_rate_limited
    team = make_team(853, nil)

    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      UpsertTeamPlayers.call(team: team)
    end

    # No touch, no dead mark: still stale, so the next nightly picks it up.
    assert_nil team.reload.last_refreshed_at
    assert_not AutoDiscovery.dead?("team:853")
    assert FootballTeam.stale.exists?(team.id)

    # Quota recovers: the next nightly run refreshes the still-stale row.
    WebMock.reset!
    stub_all_empty
    result = LeagueNightlyRefresh.call(dry_run: false, max_requests: 200)

    assert_not_nil team.reload.last_refreshed_at
    assert_equal 1, result[:teams]
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

  test "career-path first-seen team from any league gets full create + squad enqueue" do
    stub_career_path(external_team_id: 832, country: "Colombia")
    origin = make_team(830, Time.current)
    origin.competitions << Competition.create!(external_id: "144", name: "Jupiler Pro League", country: @country)
    player = make_player(832, nil)

    UpsertPlayerCareer.call(player: player, team: origin)

    full = FootballTeam.find_by!(external_id: "832")
    assert_equal "L8 FC 832", full.name
    assert_equal "Colombia", full.country.name
    assert_requested(:get, %r{/teams\?id=832}, times: 1)
    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ full.id ])
    # The career linkage is still built.
    assert player.careers.where(football_team: full).exists?
  end

  test "explicit league context always enqueues (gateless)" do
    stub_career_path(external_team_id: 833, country: "Italy")
    player = make_player(833, nil)

    UpsertPlayerCareer.call(player: player, league_id: 144)
    assert_requested(:get, %r{/teams\?id=833}, times: 1)
    assert FootballTeam.exists?(external_id: "833")
    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ FootballTeam.find_by!(external_id: "833").id ])

    FootballTeam.find_by!(external_id: "833").destroy!
    player.careers.destroy_all

    UpsertPlayerCareer.call(player: player, league_id: 39)
    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ FootballTeam.find_by!(external_id: "833").id ])
  end

  test "unknown league context fetches profile and enqueues (gateless)" do
    stub_career_path(external_team_id: 834, country: "Italy")
    player = make_player(834, nil)

    UpsertPlayerCareer.call(player: player)

    team = FootballTeam.find_by!(external_id: "834")
    assert_equal "Italy", team.country.name
    assert_requested(:get, %r{/teams\?id=834}, times: 1)
    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ team.id ])
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

  def stub_rate_limited
    stub_request(:get, /v3\.football\.api-sports\.io/).to_return(
      status: 200, body: { response: [], errors: { rateLimit: "Too many requests" } }.to_json
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

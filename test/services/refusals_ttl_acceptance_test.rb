require "test_helper"
require "tmpdir"

# L9 — Refusals/TTL + acceptance.
#
# Derived from doc/data-collection.md (not from implementation):
#   - ambiguous/no-match first-seen rows are dead with reason and carry a
#     30d TTL: inside the window the re-check is suppressed (zero HTTP),
#     after expiry the row is re-checked;
#   - name-only rows (no id source) never auto-create — squad entries
#     without a player id and Brave name-only clubs stay pending-manual
#     for a curator alias, with zero fetch HTTP;
#   - out-of-scope leagues stay pending-manual: the league fan-out records
#     teams but never enqueues squad fetches;
#   - acceptance: a career-path bare team gains its squad within one
#     nightly cycle; alias forks stay zero; over-budget stays pending with
#     zero HTTP; a dead-listed season is listed with reason and coverage
#     still passes.
class RefusalsTtlAcceptanceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebMock::API

  setup do
    WebMock.reset!
    AutoDiscovery.reset!
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    @country = Country.find_or_create_by!(name: "L9 Testland")
    @config_dir = Dir.mktmpdir
  end

  teardown do
    WebMock.reset!
    AutoDiscovery.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@config_dir)
  end

  test "dead refusal carries reason and suppresses re-checks inside the 30d TTL" do
    stub_career_path(external_team_id: 911, profile_teams: [])
    origin = make_team(910, Time.current)
    origin.competitions << Competition.create!(external_id: "39", name: "Premier League", country: @country)
    player = make_player(911, nil)

    assert_no_enqueued_jobs do
      UpsertPlayerCareer.call(player: player, team: origin)
    end
    assert_not FootballTeam.exists?(external_id: "911")
    assert_empty player.careers.reload
    assert_requested(:get, %r{/teams\?id=911}, times: 1)

    record = AutoDiscovery.dead_record("team:911")
    assert_equal "ambiguous/no-match team profile", record[:reason]
    assert AutoDiscovery.dead?("team:911")
    assert_not AutoDiscovery.recheck_due?("team:911")

    # Inside the TTL the profile re-fetch is suppressed: zero HTTP.
    WebMock.reset!
    stub_career_path(external_team_id: 911, profile_teams: [])
    assert_no_enqueued_jobs do
      UpsertPlayerCareer.call(player: player, team: origin)
    end
    assert_not_requested(:get, %r{/teams\?id=911})
    assert_not FootballTeam.exists?(external_id: "911")
  end

  test "dead refusal is re-checked after the 30d TTL expires" do
    stub_career_path(external_team_id: 912, profile_teams: [])
    origin = make_team(910, Time.current)
    origin.competitions << Competition.create!(external_id: "39", name: "Premier League", country: @country)
    player = make_player(912, nil)

    UpsertPlayerCareer.call(player: player, team: origin)
    assert AutoDiscovery.dead?("team:912")

    travel_to(31.days.from_now) do
      assert AutoDiscovery.recheck_due?("team:912")

      WebMock.reset!
      stub_career_path(external_team_id: 912, country: "England")
      UpsertPlayerCareer.call(player: player, team: origin)

      assert_requested(:get, %r{/teams\?id=912}, times: 1)
      team = FootballTeam.find_by!(external_id: "912")
      assert_equal "England", team.country.name
      assert player.careers.where(football_team: team).exists?
      assert_enqueued_with(job: FetchTeamPlayersJob, args: [ team.id ])
    end
  end

  test "name-only squad entries never auto-create and cost zero profile HTTP" do
    stub_request(:get, %r{/players/squads}).to_return(
      status: 200,
      body: {
        response: [
          { players: [
            { id: 921, name: "L9 Real Rookie", position: "Midfielder", age: 20 },
            { name: "L9 Nameless Wonder", position: "Forward" }
          ] }
        ],
        errors: {}
      }.to_json
    )
    stub_request(:get, %r{/players/profiles}).to_return(
      status: 200, body: { response: [ { player: { id: 921, name: "L9 Real Rookie" } } ], errors: {} }.to_json
    )
    team = make_team(920, Time.current)

    players = UpsertTeamPlayers.call(team: team)

    assert_equal [ "921" ], players.map { |player| player.external_id.to_s }
    assert Player.exists?(external_id: "921")
    assert_not Player.exists?(name: "L9 Nameless Wonder")
    assert_requested(:get, %r{/players/profiles\?player=921}, times: 1)
    assert_not_requested(:get, %r{/players/profiles\?player=$})
  end

  test "out-of-scope league records teams but never enqueues squads" do
    stub_request(:get, %r{/teams\?league=144}).to_return(
      status: 200,
      body: {
        response: [
          { team: { id: 931, name: "L9 Out FC", code: "L9O", country: "Belgium", national: false } }
        ],
        errors: {}
      }.to_json
    )

    job = LeagueTeamsJob.new(144, 2023, "Jupiler Pro League")
    job.define_singleton_method(:wait_time) { Time.current }
    assert_no_enqueued_jobs(only: FetchTeamPlayersJob) do
      job.perform_now
    end

    assert FootballTeam.exists?(external_id: "931")
    assert_not_requested(:get, %r{/players/squads})
  end

  test "in-scope league still enqueues squads" do
    stub_request(:get, %r{/teams\?league=39}).to_return(
      status: 200,
      body: {
        response: [
          { team: { id: 932, name: "L9 In FC", code: "L9I", country: "England", national: false } }
        ],
        errors: {}
      }.to_json
    )

    job = LeagueTeamsJob.new(39, 2023, "Premier League")
    job.define_singleton_method(:wait_time) { Time.current }
    job.perform_now

    assert_enqueued_with(job: FetchTeamPlayersJob, args: [ FootballTeam.find_by!(external_id: "932").id ])
  end

  test "acceptance: bare in-scope team gains its squad within one nightly cycle, forks zero" do
    stub_request(:get, %r{/teams\?id=941}).to_return(
      status: 200,
      body: {
        response: [ { team: { id: 941, name: "L9 Bare FC", code: "L9B", country: "England", national: false } } ],
        errors: {}
      }.to_json
    )
    stub_request(:get, %r{/players/squads}).to_return(
      status: 200,
      body: { response: [ { players: [ { id: 942, name: "L9 Nightly Rookie", position: "Midfielder", age: 20 } ] } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/players/profiles}).to_return(
      status: 200, body: { response: [ { player: { id: 942, name: "L9 Nightly Rookie" } } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/players/teams}).to_return(
      status: 200,
      body: { response: [ { team: { id: 941, name: "L9 Bare FC" }, seasons: [ 2023 ] } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/transfers}).to_return(
      status: 200, body: { response: [ { transfers: [] } ], errors: {} }.to_json
    )
    stub_request(:get, %r{/players/seasons}).to_return(
      status: 200, body: { response: [ 2023 ], errors: {} }.to_json
    )

    bare = make_team(941, nil)
    bare.competitions << Competition.create!(external_id: "39", name: "Premier League", country: @country)
    assert_empty bare.careers

    # wait_time reads Solid Queue tables, which do not exist in the test DB;
    # the squad gain below is what this ticket pins, not the stagger.
    original_wait = ApplicationJob.instance_method(:wait_time)
    ApplicationJob.define_method(:wait_time) { Time.current }
    result = nil
    begin
      perform_enqueued_jobs do
        result = Pl39NightlyRefresh.call(dry_run: false)
      end
    ensure
      ApplicationJob.define_method(:wait_time, original_wait)
    end

    assert_not_nil bare.reload.last_refreshed_at
    assert_equal 1, result[:squads_enqueued]
    rookie = Player.find_by!(external_id: "942")
    assert rookie.careers.where(football_team: bare).exists?,
      "bare team gains its squad within one nightly cycle"
    assert_empty CountryAlias.forks, "alias forks zero is the acceptance state"
  end

  test "acceptance: nightly dry-run enqueues nothing and out-of-scope bare teams stay pending-manual" do
    stub_all_empty
    bare_out = make_team(943, nil)
    bare_out.competitions << Competition.create!(external_id: "144", name: "Jupiler Pro League", country: @country)

    dry = nil
    assert_no_enqueued_jobs do
      dry = Pl39NightlyRefresh.call(dry_run: true)
    end
    assert_equal 0, dry[:squads_enqueued]

    live = nil
    assert_no_enqueued_jobs(only: FetchTeamPlayersJob) do
      live = Pl39NightlyRefresh.call(dry_run: false)
    end
    assert_not_nil bare_out.reload.last_refreshed_at
    assert_equal 0, live[:squads_enqueued]
    assert_empty bare_out.careers
  end

  test "acceptance: over-budget stays pending with zero HTTP" do
    AutoDiscovery.checkout(AutoDiscovery::DAILY_AUTO_BUDGET)
    player = make_player(951, nil)
    teams_before = FootballTeam.count

    result = nil
    assert_no_enqueued_jobs do
      result = UpsertPlayerCareer.call(player: player)
    end

    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
    assert_equal teams_before, FootballTeam.count
    assert_empty Array(result)
  end

  test "acceptance: dead-listed season is listed with reason and coverage passes" do
    team = make_team(961, Time.current)
    competition = Competition.create!(external_id: "39", name: "Premier League", country: @country)
    competition.football_teams << team
    write_allowlist_yml(
      allowlist: [],
      dead: [ { season: 2022, reason: "empty teams response" } ],
      seasons: {}
    )

    report = CoverageGate.call(league_id: 39, season: 2022, config_dir: @config_dir)

    assert report.dead
    assert_equal "empty teams response", report.dead_reason
    assert report.pass?

    lines = report.lines.join("\n")
    assert_includes lines, "dead=true reason=empty teams response"
    assert_includes lines, "coverage=PASS"
  end

  private

  def make_team(external_id, refreshed_at)
    FootballTeam.create!(
      name: "L9 Team #{external_id}", external_id: external_id.to_s,
      country: @country, last_refreshed_at: refreshed_at
    )
  end

  def make_player(external_id, refreshed_at)
    Player.create!(
      name: "L9 Player #{external_id}", external_id: external_id.to_s,
      last_refreshed_at: refreshed_at
    )
  end

  def stub_all_empty
    stub_request(:get, /v3\.football\.api-sports\.io/).to_return(
      status: 200, body: { response: [], errors: {} }.to_json
    )
  end

  def stub_career_path(external_team_id:, country: nil, profile_teams: :default)
    profile = case profile_teams
    when :default
      [ { team: { id: external_team_id, name: "L9 FC #{external_team_id}", code: "L9F", country: country || "Italy", national: false } } ]
    else
      profile_teams
    end
    stub_request(:get, %r{/players/teams}).to_return(
      status: 200,
      body: { response: [ { team: { id: external_team_id, name: "L9 FC #{external_team_id}" }, seasons: [ 2023 ] } ], errors: {} }.to_json
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

  def write_allowlist_yml(allowlist:, dead:, seasons:)
    payload = {
      "league" => 39,
      "present_year" => 2023,
      "window_truncated" => false,
      "allowlist" => allowlist,
      "dead" => dead.map { |entry| { "season" => entry[:season], "reason" => entry[:reason] } },
      "seasons" => seasons
    }
    File.write(File.join(@config_dir, "allowlist_39.yml"), YAML.dump(payload))
  end
end

require "test_helper"
require "tmpdir"
require "yaml"

# League-generic pipeline: same services with league_id != 39 use per-league
# YML artifacts (config/allowlist_<id>.yml) and a competition looked up by the passed id.
# Back-compat (39 defaults, existing 39 tasks) is covered by the Pl39* tests.
class LeagueGenericPipelineTest < ActiveSupport::TestCase
  include WebMock::API

  LEAGUE = 135
  SEASON = 2024
  PRESENT_YEAR = 2024

  setup do
    WebMock.reset!
    @config_dir = Dir.mktmpdir
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(
      FootballClient::THROTTLE_ENV_VAR
    )
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@config_dir)
  end

  test "probe with league_id writes per-league YML allowlist against league=135 URLs" do
    stub_teams(SEASON, teams_payload(20))

    result = Pl39Probe.call(league_id: LEAGUE, present_year: PRESENT_YEAR, max_requests: 1, config_dir: @config_dir)

    assert_requested(:get, "https://v3.football.api-sports.io/teams?league=135&season=#{SEASON}", times: 1)
    assert_equal [ SEASON ], result[:allowlist]
    yml = YAML.safe_load(File.read(File.join(@config_dir, "allowlist_135.yml")))
    assert_equal LEAGUE, yml["league"]
    assert_equal [ SEASON ], yml["allowlist"]
    assert_equal [], yml["dead"]
    # 39 artifact untouched.
    assert_not File.exist?(File.join(@config_dir, "allowlist_39.yml"))
  end

  test "backfill with league_id reads the per-league YML allowlist and links the passed competition" do
    write_allowlist_yml(LEAGUE, [ SEASON ], [])
    stub_teams(SEASON, teams_payload(2))
    stub_players(505, SEASON, 1, [ { id: 9999, name: "Generic Inter Player" } ])
    stub_players_empty(505, SEASON, 2)
    stub_players(506, SEASON, 1, [ { id: 9998, name: "Generic Other Player" } ])
    stub_players_empty(506, SEASON, 2)

    result = Pl39Backfill.call(league_id: LEAGUE, season: SEASON, present_year: PRESENT_YEAR, config_dir: @config_dir)

    assert_equal :completed, result[:status]
    competition = Competition.find_by!(external_id: "135")
    assert_equal competition.id, Career.first.competition_id
    assert_not_equal "39", competition.external_id
    assert CoverageGate.call(league_id: LEAGUE, season: SEASON, config_dir: @config_dir).pass?
  end

  test "coverage gate honors the per-league dead list" do
    country = Country.create!(name: "Generic Testland #{SecureRandom.hex(4)}")
    competition = Competition.create!(name: "Serie A", external_id: LEAGUE.to_s, country: country)
    team = FootballTeam.create!(name: "Generic Empty FC", country: country)
    competition.football_teams << team
    write_allowlist_yml(LEAGUE, [], [ { season: SEASON, reason: "empty teams response" } ])

    report = CoverageGate.call(league_id: LEAGUE, season: SEASON, config_dir: @config_dir)

    assert report.dead
    assert report.pass?
    assert_includes report.lines.join("\n"), "coverage league=135 season=#{SEASON}"
  end

  private

  def stub_teams(season, body)
    stub_request(:get, "https://v3.football.api-sports.io/teams?league=135&season=#{season}")
      .to_return(status: 200, body: body)
  end

  def stub_players(team_id, season, page, players)
    body = {
      response: players.map do |player|
        {
          player: {
            id: player[:id], name: player[:name],
            birth: { date: "1995-06-15" }, nationality: "Italy",
            photo: "https://example.com/#{player[:id]}.png"
          },
          statistics: [
            {
              team: { id: team_id }, league: { id: LEAGUE },
              goals: { total: 3, assists: 1 },
              games: { appearences: 5 },
              cards: { yellow: 1, red: 0 }
            }
          ]
        }
      end,
      paging: { current: page, total: 1 },
      errors: {}
    }.to_json
    stub_request(:get, "https://v3.football.api-sports.io/players?team=#{team_id}&season=#{season}&page=#{page}")
      .to_return(status: 200, body: body)
  end

  def stub_players_empty(team_id, season, page)
    body = {
      response: [],
      paging: { current: page, total: page },
      errors: {}
    }.to_json
    stub_request(:get, "https://v3.football.api-sports.io/players?team=#{team_id}&season=#{season}&page=#{page}")
      .to_return(status: 200, body: body)
  end

  def write_allowlist_yml(league_id, allowlist, dead)
    payload = {
      "league" => league_id,
      "present_year" => PRESENT_YEAR,
      "window_truncated" => false,
      "allowlist" => allowlist,
      "dead" => dead.map { |entry| { "season" => entry[:season], "reason" => entry[:reason] } },
      "seasons" => {}
    }
    File.write(File.join(@config_dir, "allowlist_#{league_id}.yml"), YAML.dump(payload))
  end

  def teams_payload(count)
    {
      response: count.times.map do |i|
        { team: { id: 505 + i, name: "Generic Team #{505 + i}", code: "G#{i}",
                  country: "Italy", national: false } }
      end,
      errors: {}
    }.to_json
  end
end

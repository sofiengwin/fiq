require "test_helper"
require "tmpdir"
require "yaml"

# L2 live-only probe: <=10 live requests per run into config/allowlist_<id>.yml
# (no data/raw/, no cache). Every run hits the API; reruns are full-cost but
# idempotent.
class Pl39ProbeTest < ActiveSupport::TestCase
  include WebMock::API

  PRESENT_YEAR = 2023
  SEASONS = PRESENT_YEAR.downto(PRESENT_YEAR - Pl39Probe::MAX_LIVE_REQUESTS + 1).to_a.freeze
  YML_FILE = "allowlist_39.yml".freeze

  setup do
    WebMock.reset!
    @config_dir = Dir.mktmpdir
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@config_dir)
  end

  test "cold run probes ten seasons with at most ten live requests and writes the YML allowlist" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }

    result = Pl39Probe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    SEASONS.each do |season|
      assert_requested(:get, teams_url(season), times: 1)
    end
    assert_operator result[:live_requests], :<=, 10
    assert_equal 10, result[:live_requests]
    assert_equal SEASONS.sort, result[:allowlist]
    assert_empty result[:dead]

    assert_equal [ YML_FILE ], Dir.children(@config_dir)
    raw = File.read(File.join(@config_dir, YML_FILE))
    assert_not_includes raw, "cache_file"
    assert_not_includes raw, "data/raw"

    yml = YAML.safe_load(raw)
    assert_equal 39, yml["league"]
    assert_equal PRESENT_YEAR, yml["present_year"]
    assert_equal SEASONS.sort, yml["allowlist"]
    assert(yml["allowlist"].all? { |season| season <= PRESENT_YEAR })
    assert_equal [], yml["dead"]
    assert_equal SEASONS.size, yml["seasons"].size
    assert_equal "ok", yml["seasons"][PRESENT_YEAR.to_s]["status"]
    assert_equal 20, yml["seasons"][PRESENT_YEAR.to_s]["team_count"]
  end

  test "rerun costs live requests again and rewrites identical YML" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }
    Pl39Probe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)
    before = File.read(File.join(@config_dir, YML_FILE))

    result = Pl39Probe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    # Live-only: no cache, so the second run re-hits the API per season.
    SEASONS.each do |season|
      assert_requested(:get, teams_url(season), times: 2)
    end
    assert_equal 10, result[:live_requests]
    assert_equal SEASONS.sort, result[:allowlist]
    assert_equal before, File.read(File.join(@config_dir, YML_FILE))
  end

  test "empty and error seasons land in the dead list with season and reason, off the allowlist" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }
    stub_teams(2014, { response: [], errors: {} }.to_json)
    stub_teams(2018, { response: [], errors: { league: "season not covered" } }.to_json)

    result = Pl39Probe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    assert_equal 10, result[:live_requests]
    assert_not_includes result[:allowlist], 2014
    assert_not_includes result[:allowlist], 2018
    assert_equal [ 2014, 2018 ], result[:dead].map { |entry| entry[:season] }
    assert result[:dead].all? { |entry| entry[:reason].is_a?(String) && entry[:reason].present? }
    assert_match(/empty/, result[:dead].find { |entry| entry[:season] == 2014 }[:reason])
    assert_match(/api error/, result[:dead].find { |entry| entry[:season] == 2018 }[:reason])

    yml = read_yml
    assert_equal [ 2014, 2018 ], yml["dead"].map { |entry| entry["season"] }

    # Oldest tried season is dead, so the window boundary was found.
    assert_equal false, result[:window_truncated]
    assert_equal false, yml["window_truncated"]
  end

  test "window is flagged truncated while the oldest tried season still has data" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }

    result = Pl39Probe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    assert_equal true, result[:window_truncated]
    assert_equal true, read_yml["window_truncated"]
  end

  test "run merges into the existing YML, preserving seasons outside the window" do
    seed_yml(
      "allowlist" => [ 2010, 2011, 2012 ],
      "dead" => [ { "season" => 2013, "reason" => "empty teams response" } ],
      "seasons" => {
        "2010" => { "status" => "ok", "team_count" => 20 },
        "2011" => { "status" => "ok", "team_count" => 20 },
        "2012" => { "status" => "ok", "team_count" => 20 },
        "2013" => { "status" => "dead", "team_count" => 0, "reason" => "empty teams response" }
      }
    )
    stub_teams(2014, teams_payload(20))
    stub_teams(2013, teams_payload(20))

    result = Pl39Probe.call(present_year: 2014, max_requests: 2, config_dir: @config_dir)

    assert_equal 2, result[:live_requests]
    # Outside-window seasons preserved; re-probed 2013 flips dead -> allowlisted.
    assert_equal [ 2010, 2011, 2012, 2013, 2014 ], result[:allowlist]
    assert_empty result[:dead]

    yml = read_yml
    assert_equal [ 2010, 2011, 2012, 2013, 2014 ], yml["allowlist"]
    assert_equal [], yml["dead"]
    assert_equal "ok", yml["seasons"]["2013"]["status"]
    assert_equal 20, yml["seasons"]["2010"]["team_count"]
  end

  test "allowlist never keeps seasons past the present year" do
    seed_yml(
      "allowlist" => [ PRESENT_YEAR, 2050 ],
      "dead" => [],
      "seasons" => {}
    )
    stub_teams(PRESENT_YEAR, teams_payload(20))

    result = Pl39Probe.call(present_year: PRESENT_YEAR, max_requests: 1, config_dir: @config_dir)

    assert_equal [ PRESENT_YEAR ], result[:allowlist]
    assert_equal [ PRESENT_YEAR ], read_yml["allowlist"]
  end

  private

  def teams_url(season)
    "https://v3.football.api-sports.io/teams?league=39&season=#{season}"
  end

  def stub_teams(season, body)
    stub_request(:get, teams_url(season)).to_return(status: 200, body: body)
  end

  def teams_payload(count)
    {
      response: count.times.map { |i| { team: { id: 30 + i, name: "Team #{30 + i}" } } },
      errors: {}
    }.to_json
  end

  def seed_yml(overrides)
    payload = {
      "league" => 39,
      "present_year" => PRESENT_YEAR,
      "window_truncated" => false
    }.merge(overrides)
    File.write(File.join(@config_dir, YML_FILE), YAML.dump(payload))
  end

  def read_yml(filename = YML_FILE)
    YAML.safe_load(File.read(File.join(@config_dir, filename)))
  end
end

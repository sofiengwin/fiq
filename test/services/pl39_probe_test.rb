require "test_helper"
require "tmpdir"

class Pl39ProbeTest < ActiveSupport::TestCase
  include WebMock::API

  PRESENT_YEAR = 2023
  SEASONS = PRESENT_YEAR.downto(PRESENT_YEAR - Pl39Probe::MAX_LIVE_REQUESTS + 1).to_a.freeze
  ARTIFACT_FILES = %w[probe_39.json seasons_allowlist_39.json dead_seasons_39.json].freeze

  setup do
    WebMock.reset!
    @cache_dir = Dir.mktmpdir
    @output_dir = Dir.mktmpdir
    @original_cache_dir = FootballClient.cache_dir
    FootballClient.cache_dir = Pathname.new(@cache_dir)
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(
      FootballClient::CACHE_ENV_VAR,
      FootballClient::THROTTLE_ENV_VAR
    )
    ENV[FootballClient::CACHE_ENV_VAR] = "true"
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
  end

  teardown do
    WebMock.reset!
    FootballClient.cache_dir = @original_cache_dir
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::CACHE_ENV_VAR)
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@cache_dir)
    FileUtils.remove_entry(@output_dir)
  end

  test "cold run probes ten seasons with at most ten live requests and writes all three artifacts" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }

    result = Pl39Probe.call(present_year: PRESENT_YEAR, output_dir: @output_dir)

    SEASONS.each do |season|
      assert_requested(:get, teams_url(season), times: 1)
    end
    assert_equal 10, result[:live_requests]
    assert_equal SEASONS.sort, result[:allowlist]
    assert_empty result[:dead]

    probe = JSON.parse(File.read(File.join(@output_dir, "probe_39.json")))
    assert_equal 39, probe["league"]
    assert_equal PRESENT_YEAR, probe["present_year"]
    assert_equal SEASONS.size, probe["seasons"].size
    assert_equal 20, probe["seasons"][PRESENT_YEAR.to_s]["team_count"]
    assert_equal "ok", probe["seasons"][PRESENT_YEAR.to_s]["status"]
    assert_match(/\.json\z/, probe["seasons"][PRESENT_YEAR.to_s]["cache_file"])
    # The cache file ref resolves to a real cached payload.
    assert File.exist?(File.join(@cache_dir, probe["seasons"][PRESENT_YEAR.to_s]["cache_file"]))

    allowlist = read_json("seasons_allowlist_39.json")
    assert_equal SEASONS.sort, allowlist
    assert(allowlist.all? { |season| season <= PRESENT_YEAR })

    assert_equal [], read_json("dead_seasons_39.json")
  end

  test "rerun after deleting artifacts makes zero live requests and reproduces identical artifacts" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }
    Pl39Probe.call(present_year: PRESENT_YEAR, output_dir: @output_dir)
    before = ARTIFACT_FILES.to_h { |file| [ file, File.read(File.join(@output_dir, file)) ] }

    # Drop the stubs: any live HTTP from here on raises instead of succeeding.
    WebMock.reset!
    ARTIFACT_FILES.each { |file| File.delete(File.join(@output_dir, file)) }

    result = Pl39Probe.call(present_year: PRESENT_YEAR, output_dir: @output_dir)

    assert_equal 0, result[:live_requests]
    assert_equal SEASONS.sort, result[:allowlist]
    after = ARTIFACT_FILES.to_h { |file| [ file, File.read(File.join(@output_dir, file)) ] }
    assert_equal before, after
  end

  test "empty and error seasons land in the dead list with season and reason, off the allowlist" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }
    stub_teams(2014, { response: [], errors: {} }.to_json)
    stub_teams(2018, { response: [], errors: { league: "season not covered" } }.to_json)

    result = Pl39Probe.call(present_year: PRESENT_YEAR, output_dir: @output_dir)

    assert_equal 10, result[:live_requests]
    assert_not_includes result[:allowlist], 2014
    assert_not_includes result[:allowlist], 2018
    assert_equal [ 2014, 2018 ], result[:dead].map { |entry| entry[:season] }
    assert result[:dead].all? { |entry| entry[:reason].is_a?(String) && entry[:reason].present? }
    assert_match(/empty/, result[:dead].find { |entry| entry[:season] == 2014 }[:reason])
    assert_match(/api error/, result[:dead].find { |entry| entry[:season] == 2018 }[:reason])

    dead_file = read_json("dead_seasons_39.json")
    assert_equal [ 2014, 2018 ], dead_file.map { |entry| entry["season"] }

    # Oldest tried season is dead, so the window boundary was found.
    assert_equal false, result[:window_truncated]
  end

  test "window is flagged truncated while the oldest tried season still has data" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }

    result = Pl39Probe.call(present_year: PRESENT_YEAR, output_dir: @output_dir)

    assert_equal true, result[:window_truncated]
    assert_equal true, read_json("probe_39.json")["window_truncated"]
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

  def read_json(filename)
    JSON.parse(File.read(File.join(@output_dir, filename)))
  end
end

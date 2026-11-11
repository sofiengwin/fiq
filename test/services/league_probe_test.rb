require "test_helper"
require "tmpdir"
require "yaml"

# L2 live-only probe: <=10 live requests per run into league_seasons memo
# rows (no YML writes, no response cache). Every run hits the API; reruns are
# idempotent.
class LeagueProbeTest < ActiveSupport::TestCase
  include WebMock::API

  PRESENT_YEAR = 2023
  SEASONS = PRESENT_YEAR.downto(PRESENT_YEAR - LeagueProbe::MAX_LIVE_REQUESTS + 1).to_a.freeze

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

  test "cold run probes ten seasons with at most ten live requests and writes memo rows" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }

    result = LeagueProbe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    SEASONS.each do |season|
      assert_requested(:get, teams_url(season), times: 1)
    end
    assert_operator result[:live_requests], :<=, 10
    assert_equal 10, result[:live_requests]
    assert_equal SEASONS.sort, result[:allowlist]
    assert_empty result[:dead]

    # DB-backed scope: one memo row per contacted season, no YML written.
    assert_empty Dir.children(@config_dir)
    assert_equal SEASONS.sort, LeagueSeason.ok_seasons_for(39, present_year: PRESENT_YEAR)
    SEASONS.each do |season|
      row = LeagueSeason.memo_for(39, season)
      assert_equal "ok", row.status
      assert_equal 20, row.team_count
      assert_not_nil row.checked_at
    end
  end

  test "rerun costs live requests again and keeps identical memos" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }
    LeagueProbe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)
    before = LeagueSeason.where(league_id: 39).order(:season).pluck(:season, :status, :team_count)

    result = LeagueProbe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    # Live-only: no cache, so the second run re-hits the API per season.
    SEASONS.each do |season|
      assert_requested(:get, teams_url(season), times: 2)
    end
    assert_equal 10, result[:live_requests]
    assert_equal SEASONS.sort, result[:allowlist]
    assert_equal before, LeagueSeason.where(league_id: 39).order(:season).pluck(:season, :status, :team_count)
  end

  test "empty and error seasons land in the dead memos with season and reason, off the allowlist" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }
    stub_teams(2014, { response: [], errors: {} }.to_json)
    stub_teams(2018, { response: [], errors: { league: "season not covered" } }.to_json)

    result = LeagueProbe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    assert_equal 10, result[:live_requests]
    assert_not_includes result[:allowlist], 2014
    assert_not_includes result[:allowlist], 2018
    assert_equal [ 2014, 2018 ], result[:dead].map { |entry| entry[:season] }
    assert result[:dead].all? { |entry| entry[:reason].is_a?(String) && entry[:reason].present? }
    assert_match(/empty/, result[:dead].find { |entry| entry[:season] == 2014 }[:reason])
    assert_match(/api error/, result[:dead].find { |entry| entry[:season] == 2018 }[:reason])

    assert_equal %w[dead dead],
      [ LeagueSeason.memo_for(39, 2014).status, LeagueSeason.memo_for(39, 2018).status ]
    assert_equal [ 2014, 2018 ], LeagueSeason.dead_entries_for(39).map { |entry| entry[:season] }

    # Oldest tried season is dead, so the window boundary was found.
    assert_equal false, result[:window_truncated]
  end

  test "window is flagged truncated while the oldest tried season still has data" do
    SEASONS.each { |season| stub_teams(season, teams_payload(20)) }

    result = LeagueProbe.call(present_year: PRESENT_YEAR, config_dir: @config_dir)

    assert_equal true, result[:window_truncated]
  end

  test "run merges with existing memos, preserving seasons outside the window" do
    [ 2010, 2011, 2012 ].each do |season|
      LeagueSeason.record_contact!(league_id: 39, season: season, status: "ok", team_count: 20)
    end
    LeagueSeason.record_contact!(
      league_id: 39, season: 2013, status: "dead",
      team_count: 0, reason: "empty teams response"
    )
    stub_teams(2014, teams_payload(20))
    stub_teams(2013, teams_payload(20))

    result = LeagueProbe.call(present_year: 2014, max_requests: 2, config_dir: @config_dir)

    assert_equal 2, result[:live_requests]
    # Outside-window seasons preserved; re-probed 2013 flips dead -> allowlisted.
    assert_equal [ 2010, 2011, 2012, 2013, 2014 ], result[:allowlist]
    assert_empty result[:dead]
    assert_equal "ok", LeagueSeason.memo_for(39, 2013).status
    assert_equal 20, LeagueSeason.memo_for(39, 2010).team_count
  end

  test "allowlist never keeps seasons past the present year" do
    LeagueSeason.record_contact!(league_id: 39, season: 2050, status: "ok", team_count: 20)
    stub_teams(PRESENT_YEAR, teams_payload(20))

    result = LeagueProbe.call(present_year: PRESENT_YEAR, max_requests: 1, config_dir: @config_dir)

    assert_equal [ PRESENT_YEAR ], result[:allowlist]
  end

  test "deprecated YML readers still parse a committed-style artifact" do
    payload = {
      "league" => 39,
      "present_year" => PRESENT_YEAR,
      "window_truncated" => false,
      "allowlist" => [ 2022, 2023 ],
      "dead" => [ { "season" => 2021, "reason" => "empty teams response" } ],
      "seasons" => {}
    }
    path = File.join(@config_dir, "allowlist_39.yml")
    File.write(path, YAML.dump(payload))

    assert_equal [ 2022, 2023 ], LeagueProbe.read_allowlist_yml(path)
    assert_equal(
      [ { season: 2021, reason: "empty teams response" } ],
      LeagueProbe.read_dead_yml(path)
    )
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
end

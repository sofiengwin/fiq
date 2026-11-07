require "test_helper"
require "tmpdir"
require "yaml"

# L3 — Capped backfill batch for one allowlisted PL 39 season (live-only).
# Derived from the live-only plan (not from implementation):
#   - single allowlisted season end-to-end makes ~40-70 live base requests
#     (teams + per-team paginated players union walked to the first empty
#     page); every run hits the API and reruns are full-cost but idempotent
#   - data:coverage (T4) passes on the backfilled season
#   - dead or future season refuses without any live player-fetch requests
#   - 500-cap trip via a stubbed/low-cap run exits cleanly and the re-run
#     re-walks live to completion
class Pl39BackfillTest < ActiveSupport::TestCase
  include WebMock::API

  SEASON = 2022
  PRESENT_YEAR = 2023

  setup do
    WebMock.reset!
    @config_dir = Dir.mktmpdir
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(
      FootballClient::THROTTLE_ENV_VAR
    )
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    write_allowlist_yml([ SEASON ], [ { season: 2021, reason: "empty teams response" } ])
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@config_dir)
  end

  test "backfills one allowlisted season within ~40 live requests with linkage and timestamps" do
    stub_teams(SEASON, [ { id: 33, name: "T5 Arsenal FC" }, { id: 40, name: "T5 Liverpool FC" } ])
    stub_players(33, SEASON, 1, [ { id: 101, name: "T5 Player One" }, { id: 102, name: "T5 Player Two" } ])
    stub_players_empty(33, SEASON, 2)
    stub_players(40, SEASON, 1, [ { id: 103, name: "T5 Player Three" } ])
    stub_players_empty(40, SEASON, 2)

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    assert_equal 5, result[:live_requests]
    assert_operator result[:live_requests], :<=, 40
    assert_equal 2, result[:teams]
    assert_equal 3, result[:players]
    assert_equal 3, result[:careers]

    competition = Competition.find_by!(external_id: "39")
    assert_equal "Premier League", competition.name

    teams = FootballTeam.where(external_id: %w[33 40])
    assert_equal 2, teams.count
    assert(teams.all? { |team| team.last_refreshed_at.present? })
    assert(teams.all? { |team| team.competitions.include?(competition) })

    players = Player.where(external_id: %w[101 102 103])
    assert_equal 3, players.count
    assert(players.all? { |player| player.last_refreshed_at.present? })

    careers = Career.all
    assert_equal 3, careers.count
    assert(careers.all? { |career| career.competition_id == competition.id })
    assert(careers.all? { |career| career.last_refreshed_at.present? })

    # Live-only: no response cache is written anywhere.
    assert_empty Dir.children(@config_dir).select { |f| f.end_with?(".json") }

    # The T4 gate measures the backfilled window as complete.
    assert CoverageGate.call(league_id: 39, season: SEASON, config_dir: @config_dir).pass?
  end

  test "immediate rerun re-hits live and stays idempotent" do
    stub_teams(SEASON, [ { id: 33, name: "T5 Rerun FC" } ])
    stub_players(33, SEASON, 1, [ { id: 111, name: "T5 Rerun Player" } ])
    stub_players_empty(33, SEASON, 2)
    first = backfill(season: SEASON)

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    # Live-only: no cache, so the rerun costs the same live requests again.
    assert_equal first[:live_requests], result[:live_requests]
    assert_equal 1, FootballTeam.where(external_id: "33").count
    assert_equal 1, Player.where(external_id: "111").count
    assert_equal 1, Career.count
  end

  test "players union dedupes by player id across teams and follows pagination" do
    stub_teams(SEASON, [ { id: 50, name: "T5 Union A FC" }, { id: 51, name: "T5 Union B FC" } ])
    stub_players(50, SEASON, 1, [ { id: 201, name: "T5 Union One" }, { id: 202, name: "T5 Union Two" } ], total_pages: 2)
    stub_players(50, SEASON, 2, [ { id: 202, name: "T5 Union Two" }, { id: 203, name: "T5 Union Three" } ], total_pages: 2)
    stub_players_empty(50, SEASON, 3)
    stub_players(51, SEASON, 1, [ { id: 203, name: "T5 Union Three" } ])
    stub_players_empty(51, SEASON, 2)

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    assert_equal 6, result[:live_requests]
    assert_equal 3, Player.count
    # Same player at two clubs in one season gets one career per club.
    assert_equal 2, Career.where(player: Player.find_by!(external_id: "203")).count
    assert_equal 4, Career.count
  end

  test "refuses a dead season with zero live requests" do
    result = backfill(season: 2021)

    assert_equal :refused, result[:status]
    assert_equal 0, result[:live_requests]
    assert_match(/dead/, result[:refusal_reason])
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
    assert_equal 0, FootballTeam.count
    assert_equal 0, Player.count
    assert_equal 0, Career.count
  end

  test "refuses a future season with zero live requests" do
    result = backfill(season: PRESENT_YEAR + 1, present_year: PRESENT_YEAR)

    assert_equal :refused, result[:status]
    assert_equal 0, result[:live_requests]
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "refuses a season missing from the allowlist with zero live requests" do
    result = backfill(season: 2020)

    assert_equal :refused, result[:status]
    assert_equal 0, result[:live_requests]
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "low-cap run stops cleanly and the re-run re-walks live to completion" do
    stub_teams(SEASON, [ { id: 60, name: "T5 Capped A FC" }, { id: 61, name: "T5 Capped B FC" } ])
    stub_players(60, SEASON, 1, [ { id: 301, name: "T5 Capped One" } ], total_pages: 2)
    stub_players(60, SEASON, 2, [ { id: 302, name: "T5 Capped Two" } ], total_pages: 2)
    stub_players_empty(60, SEASON, 3)
    stub_players(61, SEASON, 1, [ { id: 303, name: "T5 Capped Three" } ])
    stub_players_empty(61, SEASON, 2)

    capped = backfill(season: SEASON, max_requests: 2)

    assert_equal :capped, capped[:status]
    assert capped[:capped]
    assert_equal 2, capped[:live_requests]

    resumed = backfill(season: SEASON)

    assert_equal :completed, resumed[:status]
    assert_equal 6, resumed[:live_requests]
    assert_equal 2, FootballTeam.where(external_id: %w[60 61]).count
    assert_equal 3, Player.where(external_id: %w[301 302 303]).count
    assert_equal 3, Career.count
    assert CoverageGate.call(league_id: 39, season: SEASON, config_dir: @config_dir).pass?
  end

  test "refuses without an allowlist YML and names the probe task" do
    FileUtils.rm(File.join(@config_dir, "allowlist_39.yml"))

    result = backfill(season: SEASON)

    assert_equal :refused, result[:status]
    assert_equal 0, result[:live_requests]
    assert_match(/allowlist_39\.yml/, result[:refusal_reason])
    assert_match(/data:probe_pl39/, result[:refusal_reason])
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  private

  def backfill(season:, present_year: PRESENT_YEAR, max_requests: Pl39Backfill::DEFAULT_MAX_REQUESTS)
    Pl39Backfill.call(
      season: season, present_year: present_year,
      max_requests: max_requests, config_dir: @config_dir
    )
  end

  def teams_url(season)
    "https://v3.football.api-sports.io/teams?league=39&season=#{season}"
  end

  def players_url(team_id, season, page)
    "https://v3.football.api-sports.io/players?team=#{team_id}&season=#{season}&page=#{page}"
  end

  def stub_teams(season, teams)
    body = {
      response: teams.map do |team|
        { team: { id: team[:id], name: team[:name], code: "C#{team[:id]}",
                  country: "England", national: false } }
      end,
      errors: {}
    }.to_json
    stub_request(:get, teams_url(season)).to_return(status: 200, body: body)
  end

  def stub_players(team_id, season, page, players, total_pages: 1)
    body = {
      response: players.map do |player|
        {
          player: {
            id: player[:id], name: player[:name],
            birth: { date: player.fetch(:dob, "1995-06-15") },
            nationality: player.fetch(:nationality, "England"),
            photo: player.fetch(:photo, "https://example.com/#{player[:id]}.png")
          },
          statistics: player.key?(:statistics) ? player[:statistics] : [
            {
              team: { id: team_id }, league: { id: 39 },
              goals: { total: player.fetch(:goals, 3), assists: player.fetch(:assists, 2) },
              cards: { yellow: player.fetch(:cards_yellow, 1), red: player.fetch(:cards_red, 0) }
            }
          ]
        }
      end,
      paging: { current: page, total: total_pages },
      errors: {}
    }.to_json
    stub_request(:get, players_url(team_id, season, page)).to_return(status: 200, body: body)
  end

  def stub_players_empty(team_id, season, page)
    body = {
      response: [],
      paging: { current: page, total: page },
      errors: {}
    }.to_json
    stub_request(:get, players_url(team_id, season, page)).to_return(status: 200, body: body)
  end

  def write_allowlist_yml(allowlist, dead)
    payload = {
      "league" => 39,
      "present_year" => PRESENT_YEAR,
      "window_truncated" => false,
      "allowlist" => allowlist,
      "dead" => dead.map { |entry| { "season" => entry[:season], "reason" => entry[:reason] } },
      "seasons" => {}
    }
    File.write(File.join(@config_dir, "allowlist_39.yml"), YAML.dump(payload))
  end
end

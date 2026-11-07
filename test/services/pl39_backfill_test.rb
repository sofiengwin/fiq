require "test_helper"
require "tmpdir"

# T5 — Capped backfill batch for one allowlisted PL 39 season.
# Derived from tickets.md T5 "Done when" (not from implementation):
#   - single allowlisted season end-to-end makes <= ~40 live base requests
#     (plus cache writes under data/raw/); immediate rerun makes ~0 live
#   - data:coverage (T4) passes on the backfilled season
#   - dead or future season refuses without any live player-fetch requests
#   - 500-cap trip via a stubbed/low-cap run exits cleanly and resumably
class Pl39BackfillTest < ActiveSupport::TestCase
  include WebMock::API

  SEASON = 2022
  PRESENT_YEAR = 2023

  setup do
    WebMock.reset!
    @cache_dir = Dir.mktmpdir
    @raw_dir = Dir.mktmpdir
    @original_cache_dir = FootballClient.cache_dir
    FootballClient.cache_dir = Pathname.new(@cache_dir)
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(
      FootballClient::CACHE_ENV_VAR,
      FootballClient::THROTTLE_ENV_VAR
    )
    ENV[FootballClient::CACHE_ENV_VAR] = "true"
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    write_json("seasons_allowlist_39.json", [ SEASON ])
    write_json("dead_seasons_39.json", [ { season: 2021, reason: "empty teams response" } ])
  end

  teardown do
    WebMock.reset!
    FootballClient.cache_dir = @original_cache_dir
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::CACHE_ENV_VAR)
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@cache_dir)
    FileUtils.remove_entry(@raw_dir)
  end

  test "backfills one allowlisted season within ~40 live requests with linkage and timestamps" do
    stub_teams(SEASON, [ { id: 33, name: "T5 Arsenal FC" }, { id: 40, name: "T5 Liverpool FC" } ])
    stub_players(33, SEASON, 1, [ { id: 101, name: "T5 Player One" }, { id: 102, name: "T5 Player Two" } ])
    stub_players(40, SEASON, 1, [ { id: 103, name: "T5 Player Three" } ])

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    assert_equal 3, result[:live_requests]
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

    # Cache writes are visible under the T2 cache dir (data/raw/ in dev).
    assert_operator Dir.children(@cache_dir).count { |f| f.end_with?(".json") }, :>=, 3

    # The T4 gate measures the backfilled window as complete.
    assert CoverageGate.call(league_id: 39, season: SEASON, raw_dir: @raw_dir).pass?
  end

  test "immediate rerun makes ~0 live requests" do
    stub_teams(SEASON, [ { id: 33, name: "T5 Rerun FC" } ])
    stub_players(33, SEASON, 1, [ { id: 111, name: "T5 Rerun Player" } ])
    backfill(season: SEASON)

    # Drop the stubs: any live HTTP from here on raises instead of succeeding.
    WebMock.reset!

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    assert_equal 0, result[:live_requests]
    assert_equal 1, FootballTeam.where(external_id: "33").count
    assert_equal 1, Player.where(external_id: "111").count
    assert_equal 1, Career.count
  end

  test "players union dedupes by player id across teams and follows pagination" do
    stub_teams(SEASON, [ { id: 50, name: "T5 Union A FC" }, { id: 51, name: "T5 Union B FC" } ])
    stub_players(50, SEASON, 1, [ { id: 201, name: "T5 Union One" }, { id: 202, name: "T5 Union Two" } ], total_pages: 2)
    stub_players(50, SEASON, 2, [ { id: 202, name: "T5 Union Two" }, { id: 203, name: "T5 Union Three" } ], total_pages: 2)
    stub_players(51, SEASON, 1, [ { id: 203, name: "T5 Union Three" } ])

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    assert_equal 4, result[:live_requests]
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

  test "low-cap run stops cleanly and resumes on the next invocation" do
    stub_teams(SEASON, [ { id: 60, name: "T5 Capped A FC" }, { id: 61, name: "T5 Capped B FC" } ])
    stub_players(60, SEASON, 1, [ { id: 301, name: "T5 Capped One" } ], total_pages: 2)
    stub_players(60, SEASON, 2, [ { id: 302, name: "T5 Capped Two" } ], total_pages: 2)
    stub_players(61, SEASON, 1, [ { id: 303, name: "T5 Capped Three" } ])

    capped = backfill(season: SEASON, max_requests: 2)

    assert_equal :capped, capped[:status]
    assert capped[:capped]
    assert_equal 2, capped[:live_requests]

    resumed = backfill(season: SEASON)

    assert_equal :completed, resumed[:status]
    assert_equal 2, resumed[:live_requests]
    assert_equal 2, FootballTeam.where(external_id: %w[60 61]).count
    assert_equal 3, Player.where(external_id: %w[301 302 303]).count
    assert_equal 3, Career.count
    assert CoverageGate.call(league_id: 39, season: SEASON, raw_dir: @raw_dir).pass?
  end

  private

  def backfill(season:, present_year: PRESENT_YEAR, max_requests: Pl39Backfill::DEFAULT_MAX_REQUESTS)
    Pl39Backfill.call(
      season: season, present_year: present_year,
      max_requests: max_requests, raw_dir: @raw_dir
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

  def write_json(filename, payload)
    File.write(File.join(@raw_dir, filename), JSON.generate(payload))
  end
end

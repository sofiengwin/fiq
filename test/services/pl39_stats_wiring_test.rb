require "test_helper"
require "tmpdir"
require "yaml"

# L4 — Stats wiring keep: dob/nationality/photo_url + goals/assists/cards +
# competition_id + appearances from inline statistics, no minutes_played.
# Live-only: gating reads the L2 probe YML (config/allowlist_<id>.yml);
# pagination walks to the first empty page (empty-page stubs, no data/raw/).
# Derived from tickets.md T6 "Done when" (not from implementation):
#   - re-running the T5 trial season populates a spot-checked quiz-relevant
#     player (dob + nationality + photo_url) and at least one career row per
#     spot-checked player with goals present (assists/cards nullable allowed)
#     and competition_id pointing at the PL competition
#   - player without dob/nationality/photo still saves (nullable, logged)
#   - career without goals is rejected/logged (goals mandatory)
#   - minutes_played appears nowhere in code or schema
class Pl39StatsWiringTest < ActiveSupport::TestCase
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
    write_allowlist_yml([ SEASON ], [])
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@config_dir)
  end

  test "trial-season rerun populates profile and career stats on the PL competition" do
    stub_teams(SEASON, [ { id: 33, name: "T6 Arsenal FC" } ])
    stub_players(33, SEASON, 1, [
      { id: 101, name: "T6 Quiz Player", dob: "1998-05-11", nationality: "England",
        photo: "https://example.com/101.png",
        statistics: [
          { team: { id: 33 }, league: { id: 39 },
            games: { appearences: 27 },
            goals: { total: 12, assists: 7 },
            cards: { yellow: 3, red: 1 } }
        ] }
    ])
    stub_players_empty(33, SEASON, 2)

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]

    player = Player.find_by!(external_id: "101")
    assert_equal Date.new(1998, 5, 11), player.dob
    assert_equal "England", player.nationality
    assert_equal "https://example.com/101.png", player.photo_url
    assert_not_nil player.last_refreshed_at

    competition = Competition.find_by!(external_id: "39")
    career = Career.find_by!(player: player)
    assert_equal 27, career.appearances
    assert_equal 12, career.goals
    assert_equal 7, career.assists
    assert_equal 3, career.cards_yellow
    assert_equal 1, career.cards_red
    assert_equal competition.id, career.competition_id
    assert_not_nil career.last_refreshed_at
  end

  test "player without profile fields still saves with nulls" do
    stub_teams(SEASON, [ { id: 34, name: "T6 Sparse FC" } ])
    stub_players(34, SEASON, 1, [
      { id: 102, name: "T6 Sparse Player", dob: nil, nationality: nil,
        photo: nil, goals: 1 }
    ])
    stub_players_empty(34, SEASON, 2)

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    player = Player.find_by!(external_id: "102")
    assert_nil player.dob
    assert_nil player.nationality
    assert_nil player.photo_url
    assert_equal 1, Career.where(player: player).count
  end

  test "career without goals defaults to 0 so every union player keeps a career row" do
    stub_teams(SEASON, [ { id: 35, name: "T6 Goalless FC" } ])
    stub_players(35, SEASON, 1, [
      { id: 103, name: "T6 Scorer", goals: 4 },
      { id: 104, name: "T6 Unknown",
        statistics: [
          { team: { id: 35 }, league: { id: 39 },
            goals: { total: nil, assists: nil },
            cards: { yellow: nil, red: nil } }
        ] }
    ])
    stub_players_empty(35, SEASON, 2)

    result = backfill(season: SEASON)

    assert_equal :completed, result[:status]
    # The goalless player still saves, and now keeps a sparse career row
    # (goals default 0) instead of being left career-less.
    assert_not_nil Player.find_by!(external_id: "104")
    assert_equal 4, Career.find_by!(player: Player.find_by!(external_id: "103")).goals
    fallback = Career.find_by!(player: Player.find_by!(external_id: "104"))
    assert_equal 0, fallback.goals
    assert_equal 0, fallback.appearances
    assert_equal 2, result[:careers]
  end

  test "union prefers the statistics row for the team being backfilled" do
    stub_teams(SEASON, [ { id: 36, name: "T6 Mover FC" } ])
    stub_players(36, SEASON, 1, [
      { id: 105, name: "T6 Mover", goals: 9,
        statistics: [
          { team: { id: 99 }, league: { id: 39 },
            goals: { total: 20, assists: 20 },
            cards: { yellow: 9, red: 9 } },
          { team: { id: 36 }, league: { id: 39 },
            goals: { total: 9, assists: 5 },
            cards: { yellow: 2, red: 0 } }
        ] }
    ])
    stub_players_empty(36, SEASON, 2)

    backfill(season: SEASON)

    career = Career.find_by!(player: Player.find_by!(external_id: "105"))
    assert_equal 9, career.goals
    assert_equal 5, career.assists
    assert_equal 2, career.cards_yellow
    assert_equal 0, career.cards_red
  end

  test "career model rejects nil goals but allows nullable assists and cards" do
    country = Country.find_or_create_by!(name: "T6 Testland")
    team = FootballTeam.create!(name: "T6 Model FC", country: country)
    player = Player.create!(name: "T6 Model Player", external_id: "t6-model-1")

    invalid = Career.new(
      player: player, football_team: team,
      duration: Date.new(2022, 7, 1)...Date.new(2023, 7, 1),
      goals: nil
    )
    assert_not invalid.valid?
    assert_includes invalid.errors.attribute_names, :goals

    valid = Career.new(
      player: player, football_team: team,
      duration: Date.new(2021, 7, 1)...Date.new(2022, 7, 1),
      goals: 0, assists: nil, cards_yellow: nil, cards_red: nil
    )
    assert valid.valid?, valid.errors.full_messages.join(", ")
  end

  test "minutes_played appears nowhere in code or schema" do
    %w[
      app/services/pl39_backfill.rb
      app/services/upsert_team_players.rb
      app/services/upsert_player_career.rb
      app/models/career.rb
      app/models/player.rb
      db/schema.rb
    ].each do |relative|
      assert_not_includes File.read(Rails.root.join(relative)), "minutes_played",
        "#{relative} must not mention minutes_played"
    end
    assert_empty Career.column_names & %w[minutes_played]
    assert_empty Player.column_names & %w[minutes_played]
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

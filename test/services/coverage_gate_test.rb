require "test_helper"
require "tmpdir"
require "yaml"

# L5 — Coverage gate per season over the live-only YML allowlist.
# Derived from tickets.md T4 "Done when" (not from implementation):
#   - seeded season with one team missing players + one player missing careers
#     => task lists both by name and fails the gate
#   - fixed fixtures (or fully backfilled season) => per-season lines incl.
#     dead/partial + senior-apps sections and gate passes
#   - dead seasons listed, not counted as missing
#   - senior total apps >= 1 kept in DB, excluded from quiz, names reported
class CoverageGateTest < ActiveSupport::TestCase
  LEAGUE = 39
  SEASON = 2022

  setup do
    @config_dir = Dir.mktmpdir
    @country = Country.create!(name: "T4 Testland #{SecureRandom.hex(4)}")
    @competition = Competition.create!(
      name: "T4 Premier League", external_id: LEAGUE.to_s, country: @country
    )
  end

  teardown do
    FileUtils.remove_entry(@config_dir)
  end

  test "seeded gaps fail the gate and list the team and player by name" do
    full_team = add_team("T4 Full FC")
    player = add_player("T4 Capped Player")
    add_career(player, full_team, appearances: 5)
    empty_team = add_team("T4 Empty FC")
    lonely = add_player("T4 Lonely Player")

    report = gate

    assert_not report.pass?
    assert_equal 2, report.team_count
    assert_equal [ empty_team.id ], report.teams_without_players.map(&:id)
    assert_equal 1, report.players_in_scope
    assert_equal [ lonely.id ], report.players_without_careers.map(&:id)

    lines = report.lines.join("\n")
    assert_includes lines, "teams_without_players=1"
    assert_includes lines, "players_without_careers=1"
    assert_includes lines, "T4 Empty FC"
    assert_includes lines, "T4 Lonely Player"
    assert_includes lines, "coverage=FAIL"
  end

  test "fixed fixtures pass with per-season lines including dead, partial and senior sections" do
    team_a = add_team("T4 Fixed A FC")
    team_b = add_team("T4 Fixed B FC")
    player = add_player("T4 Fixed Player")
    add_career(player, team_a, appearances: 3)
    add_career(add_player("T4 Junior Player"), team_b, appearances: 0)

    report = gate

    assert report.pass?
    assert_equal 0, report.teams_without_players.size
    assert_equal 0, report.players_without_careers.size

    lines = report.lines.join("\n")
    assert_includes lines, "coverage league=39 season=2022"
    assert_includes lines, "teams=2"
    assert_includes lines, "players_in_scope=2"
    assert_includes lines, "dead=false"
    assert_includes lines, "partial=unknown"
    assert_includes lines, "allowlisted=unknown"
    assert_includes lines, "senior_players_total_apps_ge1=1"
    assert_includes lines, "senior_player name=T4 Fixed Player"
    assert_not_includes lines, "T4 Junior Player"
    assert_includes lines, "coverage=PASS"
  end

  test "senior means total career appearances >= 1 summed per player" do
    team = add_team("T4 Senior FC")
    split = add_player("T4 Split Spell Player")
    other_team = add_team("T4 Other FC")
    add_career(split, team, appearances: 0,
      duration: Date.new(2020, 7, 1)...Date.new(2021, 7, 1))
    add_career(split, other_team, appearances: 1,
      duration: Date.new(2021, 7, 1)...Date.new(2022, 7, 1))

    report = gate

    assert_equal 1, report.senior_players.size
    assert_equal "T4 Split Spell Player", report.senior_players.first[:name]
    assert_equal 1, report.senior_players.first[:total_apps]
  end

  test "dead-listed season is listed not counted as missing and passes despite gaps" do
    empty_team = add_team("T4 Dead Empty FC")
    write_allowlist_yml(
      allowlist: [],
      dead: [ { season: SEASON, reason: "empty teams response" } ],
      seasons: {}
    )

    report = gate

    assert report.dead
    assert_equal "empty teams response", report.dead_reason
    assert report.pass?

    lines = report.lines.join("\n")
    assert_includes lines, "dead=true reason=empty teams response"
    assert_includes lines, "coverage=PASS"
    assert_equal [ empty_team.id ], report.teams_without_players.map(&:id),
      "gaps are still listed even though a dead season passes"
  end

  test "partial when fewer teams retrieved than the probe listed, complete when equal" do
    add_team("T4 Partial A FC")
    add_team("T4 Partial B FC")
    write_allowlist_yml(
      allowlist: [ SEASON ],
      dead: [],
      seasons: { SEASON.to_s => { "status" => "ok", "team_count" => 5 } }
    )

    report = gate
    assert_equal true, report.partial
    assert_includes report.lines.join("\n"), "partial=true db_teams=2 probed=5"

    write_allowlist_yml(
      allowlist: [ SEASON ],
      dead: [],
      seasons: { SEASON.to_s => { "status" => "ok", "team_count" => 2 } }
    )

    assert_equal false, gate.partial
    assert_includes gate.lines.join("\n"), "partial=false db_teams=2 probed=2"
  end

  test "allowlisted season is flagged when the YML allowlist exists" do
    write_allowlist_yml(allowlist: [ SEASON ], dead: [], seasons: {})

    assert_equal true, gate.allowlisted
    assert_includes gate.lines.join("\n"), "allowlisted=true"
  end

  test "missing competition fails the gate unless the season is dead" do
    @competition.destroy!

    report = CoverageGate.call(league_id: 999, season: SEASON, config_dir: @config_dir)
    assert_not report.pass?
    assert report.competition_missing
    assert_includes report.lines.join("\n"), "competition_missing=true"
  end

  private

  def gate
    CoverageGate.call(league_id: LEAGUE, season: SEASON, config_dir: @config_dir)
  end

  def add_team(name)
    team = FootballTeam.create!(name: name, country: @country)
    @competition.football_teams << team
    team
  end

  def add_player(name)
    Player.create!(name: name, external_id: "t4-#{SecureRandom.hex(4)}")
  end

  def add_career(player, team, appearances:, duration: Date.new(2022, 7, 1)...Date.new(2023, 7, 1))
    Career.create!(player: player, football_team: team, duration: duration, appearances: appearances)
  end

  def write_allowlist_yml(allowlist:, dead:, seasons:)
    payload = {
      "league" => LEAGUE,
      "present_year" => 2023,
      "window_truncated" => false,
      "allowlist" => allowlist,
      "dead" => dead.map { |entry| { "season" => entry[:season], "reason" => entry[:reason] } },
      "seasons" => seasons
    }
    File.write(File.join(@config_dir, "allowlist_#{LEAGUE}.yml"), YAML.dump(payload))
  end
end

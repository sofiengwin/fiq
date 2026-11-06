require "test_helper"
require "rake"

# T4 — data:coverage rake wrapper: prints the CoverageGate report and exits
# 0 on pass / non-zero on fail (the shell-level acceptance in tickets.md).
class DataCoverageRakeTest < ActiveSupport::TestCase
  SEASON = 2099

  setup do
    Rake::Task.define_task(:environment)
    unless Rake::Task.task_defined?("data:coverage")
      load Rails.root.join("lib/tasks/data_coverage.rake")
    end
    @task = Rake::Task["data:coverage"]
    @task.reenable
    @country = Country.create!(name: "T4 Rake Testland #{SecureRandom.hex(4)}")
    @competition = Competition.create!(
      name: "T4 Rake Premier League", external_id: "39", country: @country
    )
  end

  teardown do
    @task.reenable if @task
  end

  test "exits non-zero and names the gaps when a team lacks players and a player lacks careers" do
    full_team = add_team("T4 Rake Full FC")
    add_career(add_player("T4 Rake Capped"), full_team)
    add_team("T4 Rake Empty FC")
    add_player("T4 Rake Lonely")

    out, = capture_io do
      @raised = assert_raises(SystemExit) { @task.invoke("39", SEASON.to_s) }
    end

    assert_not_equal 0, @raised.status
    assert_includes out, "T4 Rake Empty FC"
    assert_includes out, "T4 Rake Lonely"
    assert_includes out, "coverage=FAIL"
  end

  test "prints coverage=PASS lines and exits 0 when nothing is missing" do
    team = add_team("T4 Rake Fixed FC")
    add_career(add_player("T4 Rake Fixed Player"), team)

    out, = capture_io do
      error = assert_raises(SystemExit) { @task.invoke("39", SEASON.to_s) }
      assert_equal 0, error.status
    end

    assert_includes out, "teams_without_players=0"
    assert_includes out, "players_without_careers=0"
    assert_includes out, "senior_players_total_apps_ge1=1"
    assert_includes out, "coverage=PASS"
  end

  private

  def add_team(name)
    team = FootballTeam.create!(name: name, country: @country)
    @competition.football_teams << team
    team
  end

  def add_player(name)
    Player.create!(name: name, external_id: "t4-rake-#{SecureRandom.hex(4)}")
  end

  def add_career(player, team)
    Career.create!(
      player: player, football_team: team,
      duration: Date.new(2022, 7, 1)...Date.new(2023, 7, 1), appearances: 2
    )
  end
end

require "test_helper"

class LeagueTeamsWorkerTest < ActiveSupport::TestCase
  def setup
    LeagueTeamsWorker.jobs.clear
  end

  def teardown
    LeagueTeamsWorker.jobs.clear
  end

  test ".enqueue" do
    VCR.use_cassette("league/teams") do
      LeagueTeamsWorker.enqueue

      # Enqueu jobs for all major leagues
      assert_equal LeagueTeamsWorker.jobs.size, 5
    end
  end

  test "#perform" do
    VCR.use_cassette("league/teams") do
      LeagueTeamsWorker.new.perform(39, 2023, "English Premier League")

      competition = Competition.find_by(external_id: 39)
      assert_equal competition.teams.count, 20
      assert_equal competition.teams.count, FetchTeamPlayersWorker.jobs.size
      pp LeagueTeamsWorker.jobs
      assert_equal LeagueTeamsWorker.jobs.size, 1
    end
  end
end

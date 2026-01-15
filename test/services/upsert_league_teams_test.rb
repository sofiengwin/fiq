require "test_helper"

class UpsertLeagueTeamsTest < ActiveSupport::TestCase
  test "upsert league teams" do
    VCR.use_cassette("league/teams") do
      teams = UpsertLeagueTeams.call(league_id: 39, season: 2023, competition_name: "English Premier League")

      competition = Competition.last
      assert_equal "English Premier League", competition.name
      assert_equal "England", competition.country.name
      assert_equal [ "Manchester United", "Newcastle", "Bournemouth", "Fulham", "Wolves", "Liverpool", "Arsenal", "Burnley", "Everton", "Tottenham", "West Ham", "Chelsea", "Manchester City", "Brighton", "Crystal Palace", "Brentford", "Sheffield Utd", "Nottingham Forest", "Aston Villa", "Luton" ], competition.teams.pluck(:name)
      assert_equal teams.map(&:name), competition.teams.pluck(:name)
    end
  end
end

class LeagueTeamsWorker
  include Sidekiq::Worker

  def perform(external_league_id, season, competition_name)
    return if Time.now.year < season

    teams = UpsertLeagueTeams.call(league_id: external_league_id, season: season, competition_name: competition_name)

    teams.each do |team|
      FetchTeamPlayersWorker.perform_async(team.id)
    end

    # LeagueTeamsWorker.perform_async(
    #   external_league_id,
    #   season + 1,
    #   competition_name,
    # )
  end

  def self.enqueue
    Country::START.each do |country, competitions|
      competitions.each do |competition, league|
        LeagueTeamsWorker.perform_async(league[:league_id], league[:season], competition)
      end
    end
  end
end

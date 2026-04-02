class LeagueTeamsJob < ApplicationJob
  queue_as :team_sync

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: 30.seconds, attempts: 10


  def perform(external_league_id, season, competition_name)
    return if Time.zone.now.year < season

    teams = UpsertLeagueTeams.call(
      league_id: external_league_id,
      season: season,
      competition_name: competition_name
    )

    # Chain: queue player fetch for each team
    teams.each do |team|
      FetchTeamPlayersJob.set(wait_until: wait_time).perform_later(team.id)
    end

    # Recursively process next season
    LeagueTeamsJob.perform_later(
      external_league_id,
      season + 1,
      competition_name
    )
  rescue StandardError => e
    Rails.logger.error "LeagueTeamsJob failed: #{e.message}"
    raise
  end

  # Entry point to start ingestion
  def self.start_ingestion
    Country::START.each do |_country, competitions|
      competitions.each do |competition, league|
        LeagueTeamsJob.perform_later(league[:league_id], league[:season], competition)
      end
    end
  end
end


# LeagueTeamsJob.perform_later(39, 2000, "Premier League")
# LeagueTeamsJob.perform_later(140, 2000, "La Liga")
# LeagueTeamsJob.perform_later(61, 2000, "Ligue 1")
# LeagueTeamsJob.perform_later(78, 2000, "Bundesliga")
# LeagueTeamsJob.perform_later(135, 2000, "Serie A")

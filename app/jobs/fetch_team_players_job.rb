class FetchTeamPlayersJob < ApplicationJob
  queue_as :team_sync

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: :exponentially_longer, attempts: 10

  def perform(team_id)
    team = FootballTeam.find(team_id)
    players = UpsertTeamPlayers.call(team: team)

    # Chain: queue career fetch for each player
    players.each do |player|
      FetchPlayerCareerJob.set(wait_until: wait_time).perform_later(player.id, team_id)
    end
  end
end

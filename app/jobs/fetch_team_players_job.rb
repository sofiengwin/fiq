class FetchTeamPlayersJob < ApplicationJob
  queue_as :team_sync

  def perform(team_id)
    team = FootballTeam.find(team_id)
    players = UpsertTeamPlayers.call(team: team)

    # Chain: queue career fetch for each player
    players.each do |player|
      # FetchPlayerCareerJob.perform_later(player.id, team_id)
      FetchPlayerCareerBraveJob.perform_later(player.id)
    end
  end
end

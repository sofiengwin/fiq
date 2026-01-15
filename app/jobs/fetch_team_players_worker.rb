class FetchTeamPlayersWorker
  include Sidekiq::Worker

  def perform(team_id)
    team = Team.find(team_id)
    players = UpsertTeamPlayers.call(team: team)
    players.each do |player|
      FetchPlayerCareerWorker.perform_async(player.id, team_id)
    end
  end
end

class FetchPlayerCareerWorker
  include Sidekiq::Worker

  def perform(player_id, team_id = nil)
    player = Player.find(player_id)
    
    # Team parameter is optional and no longer used in API call
    # Kept for backward compatibility with existing jobs
    UpsertPlayerCareer.call(player: player)
  end
end

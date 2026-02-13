class FetchPlayerCareerJob < ApplicationJob
  queue_as :career_sync

  def perform(player_id, _team_id = nil)
    player = Player.find(player_id)
    UpsertPlayerCareer.call(player: player)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "FetchPlayerCareerJob: Player #{player_id} not found"
  end
end

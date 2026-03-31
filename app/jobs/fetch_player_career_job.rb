class FetchPlayerCareerJob < ApplicationJob
  queue_as :career_sync

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: :exponentially_longer, attempts: 10


  def perform(player_id, _team_id = nil)
    player = Player.find(player_id)
    UpsertPlayerCareer.call(player: player)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "FetchPlayerCareerJob: Player #{player_id} not found"
  end
end

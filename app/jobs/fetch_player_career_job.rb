class FetchPlayerCareerJob < ApplicationJob
  queue_as :career_sync

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: 30.seconds, attempts: 10


  def perform(player_id, _team_id = nil)
    player = Player.find(player_id)
    # L8: the originating squad team carries the league scope for
    # first-seen teams discovered on this player's career path (nil when
    # the player was queued directly — then scope is unknown).
    team = FootballTeam.find_by(id: _team_id) unless _team_id.nil?
    UpsertPlayerCareer.call(player: player, team: team)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "FetchPlayerCareerJob: Player #{player_id} not found"
  end
end

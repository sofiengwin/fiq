# frozen_string_literal: true

class FetchPlayerCareerBraveJob < ApplicationJob
  queue_as :career_sync

  # Rate limit: Brave API has rate limits, so we add some delay between jobs
  # limits_concurrency to: 2, key: -> { "brave_career_sync" }

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(player_id)
    player = Player.find(player_id)
    BravePlayerCareer.call(player: player)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "FetchPlayerCareerBraveJob: Player #{player_id} not found"
  end
end

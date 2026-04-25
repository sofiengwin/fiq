# frozen_string_literal: true

class UpdateTeamJob < ApplicationJob
  queue_as :team_sync

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: 30.seconds, attempts: 20
  retry_on UpdateTeam::TeamNotFoundError, wait: 1.minute, attempts: 3

  def perform(team_id)
    team = FootballTeam.find(team_id)
    UpdateTeam.call(football_team: team)
  end
end

# Enqueued entry point for LeagueBackfill (see the data:backfill_league rake).
#
# The rake task always enqueues (never runs inline) so web/CLI stays fast;
# for an inline dev run, call LeagueBackfill.call directly from a console:
#   LeagueBackfill.call(league_id: 39, season: 2022)
class BackfillLeagueJob < ApplicationJob
  queue_as :team_sync

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: 30.seconds, attempts: 10

  def perform(league_id, season, max_requests: LeagueBackfill::DEFAULT_MAX_REQUESTS, present_year: Time.zone.now.year)
    LeagueBackfill.call(
      league_id: league_id,
      season: season,
      max_requests: max_requests,
      present_year: present_year
    )
  end
end

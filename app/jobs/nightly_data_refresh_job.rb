# L6: Nightly stale-only refresh runner (see Pl39NightlyRefresh, live-only).
#
# Scheduled daily at 02:00 UTC via the `data_refresh` entry in
# config/recurring.yml. Re-syncs only rows whose `last_refreshed_at` is nil
# or older than 30 days, stops cleanly at 200 live requests per run, and
# resumes on the next night. Never blocks quiz paths on staleness.
class NightlyDataRefreshJob < ApplicationJob
  queue_as :team_sync

  # L8 priority: nightly (10) claims before auto fan-out (50); batch runs
  # synchronously outside the queue.
  queue_with_priority AutoDiscovery::NIGHTLY_PRIORITY

  retry_on FootballClient::FootballClientRateLimitExceeded, wait: 30.seconds, attempts: 10

  def perform(dry_run: false, max_requests: Pl39NightlyRefresh::DEFAULT_MAX_REQUESTS, league_id: Pl39NightlyRefresh::LEAGUE_ID)
    result = Pl39NightlyRefresh.call(dry_run: dry_run, max_requests: max_requests, league_id: league_id)
    Rails.logger.info("NightlyDataRefreshJob done #{result.inspect}")
    result
  end
end

# frozen_string_literal: true

# L8: First-seen auto-discovery — no scope gate + priority.
#
# The batch path (Pl39Backfill, cap 500, operator rake) and the nightly path
# (LeagueNightlyRefresh, cap 200, team_sync recurring) own their own counters and
# call FootballClient directly, so they never touch this path. Everything
# the LeagueTeamsJob fan-out chain spends (UpsertLeagueTeams /
# UpsertTeamPlayers / UpsertPlayerCareer HTTP) is live, uncapped per day.
#
# - Scope: none — every discovered league is treated in-scope and fans out.
#   IN_SCOPE_LEAGUE_IDS below is kept as an informational list only.
# - First-seen: a team unknown by external_id becomes a full row and its
#   squad is always enqueued. A player unknown by id in a
#   squad is created and its career fetch is enqueued by FetchTeamPlayersJob.
# - Quota: there is no daily auto counter. Quota exhaustion
#   (FootballClient::FootballClientRateLimitExceeded) propagates out of the
#   upserts instead of being swallowed, so Solid Queue retry_on backs the
#   job off; failed rows keep their stale last_refreshed_at, so the next
#   nightly (02:00 UTC) naturally retries them — that is the "retry next
#   day" mechanism.
# - Priority (Solid Queue claims lower numbers first; batch runs
#   synchronously outside the queue so it never waits): batch (sync) >
#   nightly (10) > auto (50).
# - Discovery state: logs only, no table (revisit if auto volume grows).
#   Refusals: ambiguous/no-match -> dead with reason + 30d TTL re-check note;
#   name-only rows never auto-create (needs id source or curator alias).
class AutoDiscovery < ApplicationService
  # Informational list only — every discovered league is treated in-scope
  # (doc/data-collection.md). Kept so operators can see the original five.
  IN_SCOPE_LEAGUE_IDS = [ 39, 61, 78, 135, 140 ].freeze

  # Solid Queue claims lower priority numbers first.
  BATCH_PRIORITY = 0
  NIGHTLY_PRIORITY = 10
  AUTO_PRIORITY = 50

  # Re-check horizon noted (in logs only) for dead first-seen rows.
  DEAD_RECHECK_AFTER = 30.days

  class << self
    def mutex
      @mutex ||= Mutex.new
    end

    # L9: refusal TTL — ambiguous/no-match first-seen rows are dead with
    # reason; re-checks are suppressed for 30 days (zero HTTP inside the
    # window) and allowed again after. Logs only, no table (doc:
    # "Discovery state: skipped table for now"); revisit if auto
    # volume/retries grow.
    def mark_dead(key, reason:)
      mutex.synchronize { (@dead ||= {})[key.to_s] = { reason: reason.to_s, at: Time.current } }
    end

    def clear_dead(key)
      mutex.synchronize { (@dead ||= {}).delete(key.to_s) }
    end

    def dead_record(key)
      mutex.synchronize { (@dead ||= {})[key.to_s] }
    end

    # True while a dead refusal is still inside its 30d TTL (no re-check).
    def dead?(key)
      record = dead_record(key)
      record.present? && record[:at] > DEAD_RECHECK_AFTER.ago
    end

    # True when there is no dead record or its TTL has expired.
    def recheck_due?(key)
      !dead?(key)
    end

    # No scope gate — every league is treated in-scope. Kept for
    # compatibility; always true.
    def in_scope_league?(league_id)
      true
    end

    # Discovery state, logs only (no table): one line per first-seen outcome.
    def note(outcome, **detail)
      pairs = detail.map { |key, value| "#{key}=#{value}" }.join(" ")
      Rails.logger.warn("auto_discovery outcome=#{outcome} #{pairs}".strip)
    end
  end
end

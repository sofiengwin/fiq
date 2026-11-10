# frozen_string_literal: true

# L8: First-seen auto-discovery — scope gate + daily auto budget + priority.
#
# The batch path (Pl39Backfill, cap 500, operator rake) and the nightly path
# (LeagueNightlyRefresh, cap 200, team_sync recurring) own their own counters and
# call FootballClient directly, so they never touch this budget. Everything
# the LeagueTeamsJob fan-out chain spends (UpsertLeagueTeams /
# UpsertTeamPlayers / UpsertPlayerCareer HTTP) is counted here instead.
#
# - Scope: auto-discovery fans out only for leagues [39, 135, 140, 61, 78]
#   (dev/test ON; everything else is pending-manual, never fetched).
# - First-seen: a team unknown by external_id becomes a skeleton row; its
#   squad is enqueued iff the discovering league context is in scope,
#   otherwise the skeleton stays pending-manual. A player unknown by id in a
#   squad is created and its career fetch is enqueued by FetchTeamPlayersJob.
# - Budget: 5000 live requests per day, shared by the whole auto path.
#   Checkout happens before every auto HTTP call; when the budget is spent
#   the work stays pending with zero HTTP.
# - Priority (Solid Queue claims lower numbers first; batch runs
#   synchronously outside the queue so it never waits): batch (sync) >
#   nightly (10) > auto (50).
# - Discovery state: logs only, no table (revisit if auto volume grows).
#   Refusals: ambiguous/no-match -> dead with reason + 30d TTL re-check note;
#   name-only rows never auto-create (needs id source or curator alias);
#   out-of-scope stays pending-manual.
class AutoDiscovery < ApplicationService
  # Leagues whose fan-out is ON in dev/test (doc/data-collection.md).
  IN_SCOPE_LEAGUE_IDS = [ 39, 61, 78, 135, 140 ].freeze

  # Separate from Pl39Backfill::DEFAULT_MAX_REQUESTS (500) and
  # LeagueNightlyRefresh::DEFAULT_MAX_REQUESTS (200).
  DAILY_AUTO_BUDGET = 5000

  # Solid Queue claims lower priority numbers first.
  BATCH_PRIORITY = 0
  NIGHTLY_PRIORITY = 10
  AUTO_PRIORITY = 50

  # Re-check horizon noted (in logs only) for dead first-seen rows.
  DEAD_RECHECK_AFTER = 30.days

  OverBudget = Class.new(StandardError)
  class << self
    def mutex
      @mutex ||= Mutex.new
    end

    def spent_today
      mutex.synchronize { counter_for(Date.current) }
    end

    def remaining_today
      DAILY_AUTO_BUDGET - spent_today
    end

    def over_budget?
      spent_today >= DAILY_AUTO_BUDGET
    end

    # Records n auto requests. Returns true, or false without spending when
    # the budget cannot cover n (zero HTTP must follow a false).
    def checkout(n = 1)
      mutex.synchronize do
        return false if counter_for(Date.current) + n > DAILY_AUTO_BUDGET

        store_counter(Date.current, counter_for(Date.current) + n)
        true
      end
    end

    # Same as checkout but raises OverBudget instead of returning false.
    def checkout!
      raise OverBudget, "auto budget exhausted (#{DAILY_AUTO_BUDGET}/day)" unless checkout

      true
    end

    # Test hook: forget today's spend.
    def reset!
      mutex.synchronize { @counters = {}; @dead = {} }
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

    def in_scope_league?(league_id)
      IN_SCOPE_LEAGUE_IDS.include?(league_id.to_i)
    end

    # Discovery state, logs only (no table): one line per first-seen outcome.
    def note(outcome, **detail)
      pairs = detail.map { |key, value| "#{key}=#{value}" }.join(" ")
      Rails.logger.warn("auto_discovery outcome=#{outcome} #{pairs}".strip)
    end

    private

    def counter_for(date)
      (@counters ||= {})[date.to_s] || 0
    end

    def store_counter(date, value)
      (@counters ||= {})[date.to_s] = value
    end
  end
end

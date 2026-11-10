# frozen_string_literal: true

# DB-backed league scope memo: one row per (league, season) recording the
# latest live contact (probe or backfill teams fetch). Replaces the committed
# config/allowlist_<id>.yml artifacts.
#
# - Convention range: seasons [FIRST_SEASON, present_year] are retrievable;
#   backfill refuses anything outside it with zero HTTP.
# - Dead rows are refusals with reason: a fresh dead memo (checked_at within
#   DEAD_TTL) refuses backfill with zero HTTP; an expired one is due for a
#   live re-check.
# - Coverage reads dead/partial flags from these rows. The deprecated YML
#   readers on Pl39Probe are consulted only when no memo rows exist for a
#   league (callers own that fallback, not this model).
class LeagueSeason < ApplicationRecord
  OK = "ok"
  DEAD = "dead"
  STATUSES = [ OK, DEAD ].freeze

  # Earliest season the backend can serve (probe-confirmed 2010-2026
  # retrievable, 2007-2009 dead across leagues 39/135/140/61/78).
  FIRST_SEASON = 2010

  # Fresh dead memos suppress re-contact (zero HTTP); expired ones are
  # re-checked live.
  DEAD_TTL = 30.days

  validates :league_id, presence: true
  validates :season, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Memo write on every live contact: creates or refreshes the row.
  def self.record_contact!(league_id:, season:, status:, team_count: 0, reason: nil)
    row = find_or_initialize_by(league_id: league_id.to_i, season: season.to_i)
    row.status = status.to_s
    row.team_count = team_count.to_i
    row.reason = reason
    row.checked_at = Time.current
    row.save!
    row
  end

  def self.memo_for(league_id, season)
    find_by(league_id: league_id.to_i, season: season.to_i)
  end

  def self.ok_seasons_for(league_id, present_year: Time.zone.now.year)
    where(league_id: league_id.to_i, status: OK)
      .where("season <= ?", present_year.to_i)
      .order(:season).pluck(:season)
  end

  def self.dead_entries_for(league_id)
    where(league_id: league_id.to_i, status: DEAD)
      .order(:season).map { |row| { season: row.season, reason: row.reason.to_s } }
  end

  def self.in_convention_range?(season, present_year = Time.zone.now.year)
    season.to_i >= FIRST_SEASON && season.to_i <= present_year.to_i
  end

  def ok?
    status == OK
  end

  def dead?
    status == DEAD
  end

  # True while a dead memo is still inside its TTL (no re-check).
  def fresh?
    checked_at.present? && checked_at > DEAD_TTL.ago
  end

  # True when there is no fresh memo: never checked, ok, or TTL expired.
  def recheck_due?
    !fresh?
  end
end

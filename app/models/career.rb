class Career < ApplicationRecord
  belongs_to :player
  belongs_to :football_team

  validates :duration, presence: true
  validates :appearances, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :no_overlapping_careers_for_same_team

  def self.ransackable_attributes(auth_object = nil)
    %w[id player_id football_team_id duration appearances created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[football_team player]
  end

  # Scope to find teammates with overlapping careers
  scope :overlapping_teammates, ->(min_years: 2) {
    joins(%(
      INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
      AND careers.player_id < c2.player_id
      AND careers.duration && c2.duration
    ))
    .where(%(
      EXTRACT(YEAR FROM AGE(
        LEAST(UPPER(careers.duration), UPPER(c2.duration)),
        GREATEST(LOWER(careers.duration), LOWER(c2.duration))
      )) >= ?
    ), min_years)
  }

  # Find careers that overlap with a given date range
  scope :overlapping_with, ->(date_range) {
    where("duration && ?::daterange", "[#{date_range.begin},#{date_range.end})")
  }

  # ============================================================
  # Quiz-related scopes
  # ============================================================

  # Find all players who played with a specific player
  scope :teammates_of, ->(player_id) {
    joins(%(
      INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
      AND careers.player_id != c2.player_id
      AND careers.duration && c2.duration
    ))
    .where("c2.player_id = ?", player_id)
    .select("DISTINCT careers.player_id")
  }

  # Find teammates with configurable minimum overlap duration (1-4 years)
  scope :teammates_with_min_overlap, ->(player_id, min_years: 1) {
    min_years = min_years.clamp(1, 4)
    min_days = min_years * 365

    joins(%(
      INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
      AND careers.player_id != c2.player_id
      AND careers.duration && c2.duration
      AND (LEAST(UPPER(careers.duration), UPPER(c2.duration)) -
           GREATEST(LOWER(careers.duration), LOWER(c2.duration))) >= #{min_days}
    ))
    .where("c2.player_id = ?", player_id)
  }

  # Find the common teams where two players overlapped
  scope :common_teams_between, ->(player1_id, player2_id) {
    select("careers.football_team_id,
            GREATEST(LOWER(careers.duration), LOWER(c2.duration)) as overlap_start,
            LEAST(UPPER(careers.duration), UPPER(c2.duration)) as overlap_end")
    .joins(%(
      INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
      AND c2.player_id = #{ActiveRecord::Base.connection.quote(player2_id)}
      AND careers.duration && c2.duration
    ))
    .where(player_id: player1_id)
  }

  private

  # Only prevent overlapping careers for the SAME team
  # Players can be at different teams simultaneously (e.g., Porto B + Porto first team)
  def no_overlapping_careers_for_same_team
    return unless player && duration && football_team_id

    overlapping = player.careers
      .where(football_team_id: football_team_id)
      .where.not(id: id)
      .where("duration && ?::daterange", "[#{duration.begin},#{duration.end})")

    if overlapping.exists?
      errors.add(:duration, "overlaps with an existing career at the same team")
    end
  end
end

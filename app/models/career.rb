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

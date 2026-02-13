class Career < ApplicationRecord
  belongs_to :player
  belongs_to :football_team

  validates :duration, presence: true
  validate :no_overlapping_careers

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

  def no_overlapping_careers
    return unless player && duration

    overlapping = player.careers
      .where.not(id: id)
      .where("duration && ?::daterange", "[#{duration.begin},#{duration.end})")

    if overlapping.exists?
      errors.add(:duration, "overlaps with an existing career")
    end
  end
end

class Player < ApplicationRecord
  has_many :careers, dependent: :destroy
  has_many :football_teams, through: :careers

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

  def self.ransackable_attributes(auth_object = nil)
    [ "age", "appearances", "created_at", "external_id", "first_name", "id", "id_value", "last_name", "name", "position", "updated_at" ]
  end

  def journey
    careers.includes(:football_team).order("careers.duration").map { |career|
      team_name = career.football_team.name
      duration = format_duration(career.duration)
      "#{team_name} :: #{duration}"
    }.join("<br><br>")
  end

  def fetch_data
    FetchPlayerCareerJob.perform_later(id, nil)
  end

  private

  def format_duration(range)
    start_date = range.begin&.strftime("%Y") || "?"
    end_date = if range.end.nil? || range.end.is_a?(Float)
      "Present"
    else
      range.end.strftime("%Y")
    end
    "#{start_date} - #{end_date}"
  end

  # TODO: exclude national team careers
  scope :with_competitions, ->(count) {
    joins(careers: { football_team: :competitions })
      .group("players.id")
      .having("COUNT(DISTINCT competitions_football_teams.competition_id) >= ?", count)
  }

  # ============================================================
  # Quiz-related scopes
  # ============================================================

  # Find players who played in specific competitions
  scope :played_in_competitions, ->(*competition_ids) {
    joins(careers: { football_team: :competitions })
      .where(competitions: { id: competition_ids })
      .group("players.id")
      .having("COUNT(DISTINCT competitions.id) = ?", competition_ids.size)
  }

  # Find players who played in specific countries
  scope :played_in_countries, ->(*country_ids) {
    joins(careers: { football_team: :country })
      .where(countries: { id: country_ids })
      .group("players.id")
      .having("COUNT(DISTINCT countries.id) = ?", country_ids.size)
  }

  # Find players with their country career history
  scope :countries_played_in, -> {
    joins(careers: { football_team: :country })
      .select("players.*, ARRAY_AGG(DISTINCT countries.name) as country_names, COUNT(DISTINCT countries.id) as country_count")
      .group("players.id")
  }

  # Find players with minimum appearances at a single club
  scope :with_appearances_at_club, ->(threshold) {
    joins(:careers)
      .where("careers.appearances >= ?", threshold)
      .distinct
  }

  # Find players without high appearances at any club
  scope :without_high_appearances, ->(threshold) {
    joins(:careers)
      .group("players.id")
      .having("MAX(careers.appearances) < ?", threshold)
  }

  # Find players who played for multiple clubs
  scope :with_min_clubs, ->(count) {
    joins(:careers)
      .group("players.id")
      .having("COUNT(DISTINCT careers.football_team_id) >= ?", count)
  }

  # Get teammates with configurable overlap (1-4 years)
  def teammates(min_overlap_years: 1)
    min_overlap_years = min_overlap_years.clamp(1, 4)

    Player.joins(:careers)
      .joins(%(
        INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
        AND careers.player_id != c2.player_id
        AND careers.duration && c2.duration
      ))
      .where("c2.player_id = ?", id)
      .where(%(
        EXTRACT(YEAR FROM AGE(
          LEAST(UPPER(careers.duration), UPPER(c2.duration)),
          GREATEST(LOWER(careers.duration), LOWER(c2.duration))
        )) >= ?
      ), min_overlap_years)
      .distinct
  end

  # Check if this player played with another player
  def played_with?(other_player, min_overlap_years: 1)
    min_overlap_years = min_overlap_years.clamp(1, 4)
    min_overlap_days = min_overlap_years * 365

    Career.where(player_id: id)
      .joins(%(
        INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
        AND c2.player_id = #{other_player.id}
        AND careers.duration && c2.duration
        AND (LEAST(UPPER(careers.duration), UPPER(c2.duration)) -
             GREATEST(LOWER(careers.duration), LOWER(c2.duration))) >= #{min_overlap_days}
      ))
      .exists?
  end
end

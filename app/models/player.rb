class Player < ApplicationRecord
  has_many :careers, dependent: :destroy
  has_many :football_teams, through: :careers

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

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
end

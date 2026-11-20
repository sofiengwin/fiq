class Competition < ApplicationRecord
  belongs_to :country
  has_and_belongs_to_many :football_teams
  has_many :players, through: :football_teams

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

  # Top 5 European leagues (external API league_ids): England PL (39),
  # Spain La Liga (140), Germany Bundesliga (78), Italy Serie A (135),
  # France Ligue 1 (61). Quizzes are limited to this data.
  TOP_FIVE_EXTERNAL_IDS = %w[39 140 78 135 61].freeze

  scope :top_five, -> { where(external_id: TOP_FIVE_EXTERNAL_IDS) }

    def self.ransackable_attributes(auth_object = nil)
    %w[country_id created_at external_id id name updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[football_teams country]
  end
end

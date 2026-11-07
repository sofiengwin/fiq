class FootballTeam < ApplicationRecord
  belongs_to :country
  has_many :careers, dependent: :destroy
  has_many :players, through: :careers
  has_and_belongs_to_many :competitions

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

  # T7: staleness marker for the nightly refresh — nil or older than 30 days.
  scope :stale, ->(threshold = 30.days.ago) {
    where("last_refreshed_at IS NULL OR last_refreshed_at <= ?", threshold)
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[code country_id created_at external_id id name updated_at national]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[careers competitions country players]
  end

  def players_count
    players.distinct.count
  end

  def fetch_data
    FetchTeamPlayersJob.perform_later(id)
  end
end

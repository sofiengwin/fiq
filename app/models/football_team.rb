class FootballTeam < ApplicationRecord
  belongs_to :country
  has_many :careers, dependent: :destroy
  has_many :players, through: :careers
  has_and_belongs_to_many :competitions

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

  def players_count
    players.distinct.count
  end

  def fetch_data
    FetchTeamPlayersJob.perform_later(id)
  end
end

class Country < ApplicationRecord
  has_many :football_teams, dependent: :destroy
  has_many :competitions, dependent: :destroy
  has_many :players, through: :football_teams

  validates :name, presence: true, uniqueness: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id code id_value name updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[football_teams competitions]
  end

  # Configuration constant for leagues to track
  START = {
    "England" => {
      "English Premier League" => {
        league_id: 39,
        season: 2020
      }
    },
    "Spain" => {
      "La Liga" => {
        league_id: 140,
        season: 2023
      }
    },
    "France" => {
      "Ligue 1" => {
        league_id: 61,
        season: 2023
      }
    },
    "Germany" => {
      "Bundesliga" => {
        league_id: 78,
        season: 2023
      }
    },
    "Italy" => {
      "Serie A" => {
        league_id: 135,
        season: 2023
      }
    }
  }.freeze
end

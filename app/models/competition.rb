class Competition < ApplicationRecord
  belongs_to :country
  has_and_belongs_to_many :football_teams

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true
end

class Competition < ApplicationRecord
  belongs_to :country
  has_and_belongs_to_many :football_teams
  has_many :players, through: :football_teams

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

    def self.ransackable_attributes(auth_object = nil)
    %w[country_id created_at external_id id name updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[football_teams country]
  end
end

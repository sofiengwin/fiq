class Team < ApplicationRecord
  belongs_to :country
  has_many :careers
  has_many :players, through: :careers

  has_and_belongs_to_many :competitions

    rails_admin do
    list do
      field :name
      field :code
      field :country
      field :players_count
    end

    show do
      field :name
      field :code
      field :country
      field :external_id
      field :competitions
      group :players do
        field :players
      end
    end
  end

  def players_count
    players.count
  end

  def fetch_data
    FetchTeamPlayersWorker.perform_async(self.id)
  end
end

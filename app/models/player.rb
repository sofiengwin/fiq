class Player < ApplicationRecord
  has_many :careers

  rails_admin do
    show do
      field :name
      field :position
      field :external_id
      field :journey do
        formatted_value do
          bindings[:object].journey.html_safe
        end
      end
      group :careers do
        field :journey do
          formatted_value do
            bindings[:object].journey.html_safe
          end
        end
      end
    end
  end

  def journey
    careers.map { |career| [ career.team.name, career.duration.to_s ].join(" :: ") }.join("<br><br>")
  end

  def fetch_data
    FetchPlayerCareerWorker.perform_async(self.id, nil)
  end

  private

  # def fetch_player_careers
  #   UpsertPlayerCareerWorker.perform_async(player_id: self.id)
  # end

  def current_team
    @current_team ||= careers.order(start_date: :desc).first&.team
  end

  def all_teammates
    Player.joins(:careers)
      teams = careers.pluck(:team_id) - [ current_team.id ]
      .where(careers: { team_id: teams })
      .where.not(id: id)
      .where(
        'EXISTS (
          SELECT 1 FROM careers c1
          WHERE c1.player_id = ?
          AND c1.team_id = careers.team_id
          AND (
            (c1.start_date <= careers.end_date OR careers.end_date IS NULL)
            AND (c1.end_date >= careers.start_date OR c1.end_date IS NULL)
          )
        )', id
      )
      .distinct
  end
end

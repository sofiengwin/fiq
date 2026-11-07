class AddStatsPrereqAndStalenessFields < ActiveRecord::Migration[8.1]
  def change
    # Players: quiz-required profile fields + staleness marker.
    add_column :players, :dob, :date
    add_column :players, :nationality, :string
    add_column :players, :photo_url, :string
    add_column :players, :last_refreshed_at, :datetime
    add_index :players, :last_refreshed_at

    # Teams: staleness marker only.
    add_column :football_teams, :last_refreshed_at, :datetime
    add_index :football_teams, :last_refreshed_at

    # Careers: quiz-required stat fields + competition link + staleness marker.
    # goals stays nullable on day one so existing rows survive; presence is
    # enforced at the model/upsert layer (T6), not via DB not-null.
    add_column :careers, :goals, :integer, default: 0
    add_column :careers, :assists, :integer
    add_column :careers, :cards_yellow, :integer
    add_column :careers, :cards_red, :integer
    add_reference :careers, :competition, foreign_key: true
    add_column :careers, :last_refreshed_at, :datetime
    add_index :careers, :last_refreshed_at
  end
end

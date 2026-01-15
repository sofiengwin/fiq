class AddLeagueToTeams < ActiveRecord::Migration[8.1]
  def change
    add_reference :teams, :league, null: false, foreign_key: true
  end
end

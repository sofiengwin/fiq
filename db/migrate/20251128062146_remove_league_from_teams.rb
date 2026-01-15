class RemoveLeagueFromTeams < ActiveRecord::Migration[8.1]
  def change
    remove_reference :teams, :league, null: false, foreign_key: true
  end
end

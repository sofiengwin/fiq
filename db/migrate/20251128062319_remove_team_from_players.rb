class RemoveTeamFromPlayers < ActiveRecord::Migration[8.1]
  def change
    remove_reference :players, :team, null: false, foreign_key: true
  end
end

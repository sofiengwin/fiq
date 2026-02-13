class CreateFootballTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :football_teams do |t|
      t.string :name, null: false
      t.string :code
      t.string :external_id
      t.references :country, foreign_key: true
      t.timestamps
    end
    add_index :football_teams, :external_id, unique: true
  end
end

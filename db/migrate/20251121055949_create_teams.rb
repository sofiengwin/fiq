class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name
      t.string :code
      t.references :country, null: true, foreign_key: true
      t.string :external_id

      t.timestamps
    end
  end
end

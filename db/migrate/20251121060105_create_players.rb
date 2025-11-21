class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.string :name
      t.string :position
      t.string :first_name
      t.string :last_name
      t.references :team, null: false, foreign_key: true
      t.string :external_id
      t.integer :age
      t.integer :appearances

      t.timestamps
    end
  end
end

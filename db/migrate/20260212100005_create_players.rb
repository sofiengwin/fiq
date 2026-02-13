class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.string :name, null: false
      t.string :first_name
      t.string :last_name
      t.string :external_id
      t.string :position
      t.integer :age
      t.integer :appearances, default: 0
      t.timestamps
    end
    add_index :players, :external_id, unique: true
  end
end

class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|
      t.string :name, null: false
      t.string :code
      t.timestamps
    end
    add_index :countries, :name, unique: true
  end
end

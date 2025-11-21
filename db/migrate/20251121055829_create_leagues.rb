class CreateLeagues < ActiveRecord::Migration[8.1]
  def change
    create_table :leagues do |t|
      t.string :name
      t.string :external_id
      t.references :country, null: false, foreign_key: true

      t.timestamps
    end
  end
end

class CreateCompetitions < ActiveRecord::Migration[8.1]
  def change
    create_table :competitions do |t|
      t.string :name, null: false
      t.string :external_id
      t.references :country, foreign_key: true
      t.timestamps
    end
    add_index :competitions, :external_id, unique: true
  end
end

class CreateCompetitions < ActiveRecord::Migration[8.1]
  def change
    create_table :competitions do |t|
      t.string :name
      t.string :external_id
      t.references :country, null: true, foreign_key: true

      t.timestamps
    end
  end
end

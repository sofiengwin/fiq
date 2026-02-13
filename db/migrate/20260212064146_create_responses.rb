class CreateResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :responses do |t|
      t.references :quiz_attempt, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true
      t.integer :time_taken_ms
      t.integer :score_awarded
      t.datetime :submitted_at

      t.timestamps
    end
  end
end

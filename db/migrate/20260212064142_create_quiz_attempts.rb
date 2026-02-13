class CreateQuizAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :quiz_attempts do |t|
      t.references :quiz, null: false, foreign_key: true
      t.integer :total_score
      t.integer :streak
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end

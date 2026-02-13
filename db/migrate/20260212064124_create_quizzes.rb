class CreateQuizzes < ActiveRecord::Migration[8.1]
  def change
    create_table :quizzes do |t|
      t.string :title
      t.text :description
      t.integer :time_limit_seconds
      t.string :scoring_mode

      t.timestamps
    end
  end
end

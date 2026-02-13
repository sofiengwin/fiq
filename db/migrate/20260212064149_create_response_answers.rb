class CreateResponseAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :response_answers do |t|
      t.references :response, null: false, foreign_key: true
      t.references :answer_option, null: false, foreign_key: true

      t.timestamps
    end
  end
end

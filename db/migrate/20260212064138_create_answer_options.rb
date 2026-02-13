class CreateAnswerOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :answer_options do |t|
      t.references :question, null: false, foreign_key: true
      t.integer :order_index
      t.string :text
      t.boolean :is_correct
      t.string :color

      t.timestamps
    end
  end
end

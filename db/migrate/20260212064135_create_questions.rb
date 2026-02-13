class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.references :quiz, null: false, foreign_key: true
      t.integer :order_index
      t.text :text
      t.string :image_url
      t.integer :time_limit_seconds
      t.integer :points

      t.timestamps
    end
  end
end

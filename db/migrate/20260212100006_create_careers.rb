class CreateCareers < ActiveRecord::Migration[8.1]
  def change
    create_table :careers do |t|
      t.references :player, null: false, foreign_key: true
      t.references :football_team, null: false, foreign_key: true
      t.daterange :duration
      t.timestamps
    end

    # Index for overlapping career queries using GiST
    add_index :careers, :duration, using: :gist
  end
end

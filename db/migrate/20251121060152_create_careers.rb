class CreateCareers < ActiveRecord::Migration[8.1]
  def change
    create_table :careers do |t|
      t.references :player, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date

      t.timestamps
    end
  end
end

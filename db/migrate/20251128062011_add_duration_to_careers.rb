class AddDurationToCareers < ActiveRecord::Migration[8.1]
  def change
    add_column :careers, :duration, :daterange
  end
end

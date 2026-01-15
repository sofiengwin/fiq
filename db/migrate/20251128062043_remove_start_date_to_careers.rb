class RemoveStartDateToCareers < ActiveRecord::Migration[8.1]
  def change
    remove_column :careers, :start_date
    remove_column :careers, :end_date
  end
end

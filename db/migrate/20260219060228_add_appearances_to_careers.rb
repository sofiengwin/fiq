class AddAppearancesToCareers < ActiveRecord::Migration[8.1]
  def change
    add_column :careers, :appearances, :integer, default: 0
  end
end

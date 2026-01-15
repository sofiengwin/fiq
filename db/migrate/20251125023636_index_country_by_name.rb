class IndexCountryByName < ActiveRecord::Migration[8.1]
  def change
    add_index :countries, :name
  end
end

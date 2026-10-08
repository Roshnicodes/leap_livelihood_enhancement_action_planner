class CreateDashboardLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :dashboard_links do |t|
      t.string :key, null: false
      t.text :url, null: false
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :dashboard_links, :key, unique: true
  end
end

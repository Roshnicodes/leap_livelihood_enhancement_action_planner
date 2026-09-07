class AddImportFlagToBliActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :bli_activities, :import_flag, :integer, default: 0, null: false

    add_index :bli_activities, [ :import_flag, :active, :project_name, :vertical_name, :bli_code, :id ],
      name: "idx_bli_activities_current_admin_lookup"
  end
end

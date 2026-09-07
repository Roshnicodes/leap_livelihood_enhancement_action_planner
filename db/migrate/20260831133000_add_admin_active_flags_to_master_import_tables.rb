class AddAdminActiveFlagsToMasterImportTables < ActiveRecord::Migration[8.1]
  def change
    add_column :action_plan_vertical_mappings, :active, :boolean, default: true, null: false
    add_column :project_ownerships, :active, :boolean, default: true, null: false
    add_column :bli_activities, :active, :boolean, default: true, null: false
    add_column :parent_activity_assignments, :active, :boolean, default: true, null: false
    add_column :employee_vertical_mappings, :active, :boolean, default: true, null: false

    add_index :action_plan_vertical_mappings, [ :active, :employee_code, :state_code, :asa_theme_id ],
      name: "idx_action_plan_vertical_mappings_active_lookup"
    add_index :project_ownerships, [ :active, :po_id, :project_name ],
      name: "idx_project_ownerships_active_lookup"
    add_index :bli_activities, [ :active, :project_name, :vertical_name, :bli_code, :id ],
      name: "idx_bli_activities_active_admin_lookup"
    add_index :parent_activity_assignments, [ :active, :source_parent_activity ],
      name: "idx_parent_activity_assignments_active_lookup"
    add_index :employee_vertical_mappings, [ :active, :employee_id, :vertical_percent_id ],
      name: "idx_employee_vertical_mappings_active_lookup"
  end
end

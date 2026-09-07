class AddAdminActiveFlagsToActionPlanAdminTables < ActiveRecord::Migration[8.1]
  def change
    add_column :action_plan_rows, :active, :boolean, default: true, null: false
    add_column :action_plan_fco_mappings, :active, :boolean, default: true, null: false

    add_index :action_plan_rows, [ :import_flag, :active, :project_name, :id ],
      name: "idx_action_plan_rows_active_admin"
    add_index :action_plan_fco_mappings, [ :active, :employee_id, :fco_id ],
      name: "idx_action_plan_fco_active_employee"
  end
end

class VersionActionPlanImportRows < ActiveRecord::Migration[8.1]
  def change
    add_column :action_plan_rows, :id_new, :string
    add_column :action_plan_rows, :statte, :string
    add_column :action_plan_rows, :project_id, :string
    add_column :action_plan_rows, :project_owner, :string
    add_column :action_plan_rows, :user_id, :string
    add_column :action_plan_rows, :user_name, :string
    add_column :action_plan_rows, :responsibel, :string
    add_column :action_plan_rows, :import_flag, :integer, default: 0, null: false
    add_column :action_plan_rows, :imported_at, :datetime

    add_index :action_plan_rows, :import_flag
    add_index :action_plan_rows, :imported_at
    add_index :action_plan_rows, :id_new
  end
end

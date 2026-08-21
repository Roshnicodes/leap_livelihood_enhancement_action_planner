class CreateActionPlanMonthChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :action_plan_month_changes do |t|
      t.string :po_id, null: false
      t.string :project_name, null: false
      t.string :statte
      t.string :user_id
      t.string :to_id
      t.string :asa_theme_id
      t.string :asa_activity_id
      t.string :month, null: false
      t.integer :original_value, default: 0, null: false
      t.integer :changed_value, default: 0, null: false
      t.string :status, default: "pending", null: false
      t.string :source, default: "user_edit", null: false
      t.references :action_plan_submission, foreign_key: true
      t.references :changed_by, foreign_key: { to_table: :users }
      t.datetime :last_applied_at
      t.datetime :merged_at
      t.timestamps
    end

    add_index :action_plan_month_changes,
      [ :po_id, :project_name, :statte, :user_id, :to_id, :asa_theme_id, :asa_activity_id, :month ],
      unique: true,
      name: "idx_action_plan_month_changes_identity"
    add_index :action_plan_month_changes, [ :status, :updated_at ], name: "idx_action_plan_month_changes_status"
    add_index :action_plan_month_changes, [ :project_name, :status ], name: "idx_action_plan_month_changes_project_status"
  end
end

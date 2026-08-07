class CreateAchievementEntryDetailsAndIndexes < ActiveRecord::Migration[8.1]
  def change
    create_table :achievement_entry_details do |t|
      t.references :action_plan_row, null: false, foreign_key: true
      t.string :month, null: false
      t.text :remark
      t.timestamps
    end

    add_index :achievement_entry_details,
      [ :action_plan_row_id, :month ],
      unique: true,
      name: "idx_achievement_entry_details_row_month"

    # Hot paths for Achievement Entry / Action Plan filters
    add_index :action_plan_rows, :user_id, name: "index_action_plan_rows_on_user_id"
    add_index :action_plan_rows,
      [ :import_flag, :user_id ],
      name: "idx_action_plan_rows_active_user"
    add_index :action_plan_rows,
      [ :import_flag, :user_id, :to_id ],
      name: "idx_action_plan_rows_active_user_to"
    add_index :action_plan_rows,
      [ :import_flag, :user_id, :to_id, :project_name ],
      name: "idx_action_plan_rows_active_user_to_project"
    add_index :action_plan_rows,
      [ :import_flag, :to_id, :project_name ],
      name: "idx_action_plan_rows_active_to_project"
    add_index :action_plan_rows,
      [ :statte, :asa_theme_id ],
      name: "idx_action_plan_rows_state_theme"

    add_index :action_plan_vertical_mappings,
      [ :state_code, :asa_theme_id ],
      name: "idx_action_plan_vertical_mappings_state_theme"

    add_index :achievement_submission_rows,
      [ :month, :action_plan_row_id ],
      name: "idx_achievement_submission_rows_month_row"

    add_index :achievement_submissions,
      [ :to_id, :project_name, :month, :status ],
      name: "idx_achievement_submissions_scope_status"
  end
end

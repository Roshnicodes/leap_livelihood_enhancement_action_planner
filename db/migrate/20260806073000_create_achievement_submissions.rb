class CreateAchievementSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :achievement_submissions do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :fco_id, null: false
      t.string :fco_name, null: false
      t.string :to_id, null: false
      t.string :to_name
      t.string :project_name, null: false
      t.string :po_id, null: false
      t.string :state_code
      t.string :asa_theme_id, null: false
      t.string :month, null: false
      t.string :status, default: "pending", null: false
      t.string :current_stage, default: "vertical", null: false
      t.text :submission_remark
      t.references :vertical_approver, foreign_key: { to_table: :employees }
      t.references :po_approver, foreign_key: { to_table: :employees }
      t.references :coo_approver, foreign_key: { to_table: :employees }
      t.references :director_approver, foreign_key: { to_table: :employees }
      t.datetime :submitted_at, null: false
      t.datetime :vertical_reviewed_at
      t.datetime :po_reviewed_at
      t.datetime :coo_reviewed_at
      t.datetime :director_reviewed_at
      t.text :vertical_remark
      t.text :po_remark
      t.text :coo_remark
      t.text :director_remark

      t.timestamps
    end

    add_index :achievement_submissions, [ :status, :current_stage, :submitted_at ]
    add_index :achievement_submissions, [ :employee_id, :project_name, :to_id, :month ], name: "idx_achievement_submission_employee_scope"
    add_index :achievement_submissions, [ :vertical_approver_id, :status, :current_stage ], name: "idx_achievement_vertical_pending"
    add_index :achievement_submissions, [ :po_approver_id, :status, :current_stage ], name: "idx_achievement_po_pending"
    add_index :achievement_submissions, [ :coo_approver_id, :status, :current_stage ], name: "idx_achievement_coo_pending"
    add_index :achievement_submissions, [ :director_approver_id, :status, :current_stage ], name: "idx_achievement_director_pending"

    create_table :achievement_submission_rows do |t|
      t.references :achievement_submission, null: false, foreign_key: true
      t.references :action_plan_row, null: false, foreign_key: true
      t.string :month, null: false
      t.integer :target_value, default: 0, null: false
      t.integer :achievement_value, default: 0, null: false

      t.timestamps
    end

    add_index :achievement_submission_rows,
      [ :action_plan_row_id, :month, :achievement_submission_id ],
      unique: true,
      name: "idx_achievement_submission_rows_unique"
  end
end

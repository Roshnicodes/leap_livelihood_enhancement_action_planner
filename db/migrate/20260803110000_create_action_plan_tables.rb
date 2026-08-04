class CreateActionPlanTables < ActiveRecord::Migration[8.1]
  def change
    create_table :project_ownerships do |t|
      t.string :po_id, null: false
      t.string :project_name, null: false
      t.string :project_owner_id
      t.string :po_name
      t.string :email_id

      t.timestamps
    end

    add_index :project_ownerships, [ :po_id, :project_name ], unique: true
    add_index :project_ownerships, :project_name
    add_index :project_ownerships, :project_owner_id
    add_index :project_ownerships, :email_id

    create_table :action_plan_rows do |t|
      t.string :po_id, null: false
      t.string :project_name, null: false
      t.string :to_id
      t.string :to_name
      t.string :theme_id
      t.text :theme
      t.string :activity_id
      t.text :activity
      t.string :unit_type
      t.text :a_remark
      t.integer :apr, default: 0, null: false
      t.integer :may, default: 0, null: false
      t.integer :jun, default: 0, null: false
      t.integer :jul, default: 0, null: false
      t.integer :aug, default: 0, null: false
      t.integer :sep, default: 0, null: false
      t.integer :oct, default: 0, null: false
      t.integer :nov, default: 0, null: false
      t.integer :dec, default: 0, null: false
      t.integer :jan, default: 0, null: false
      t.integer :feb, default: 0, null: false
      t.integer :mar, default: 0, null: false
      t.integer :apr_t, default: 0, null: false
      t.integer :may_t, default: 0, null: false
      t.integer :jun_t, default: 0, null: false
      t.integer :jul_t, default: 0, null: false
      t.integer :aug_t, default: 0, null: false
      t.integer :sep_t, default: 0, null: false
      t.integer :oct_t, default: 0, null: false
      t.integer :nov_t, default: 0, null: false
      t.integer :dec_t, default: 0, null: false
      t.integer :jan_t, default: 0, null: false
      t.integer :feb_t, default: 0, null: false
      t.integer :mar_t, default: 0, null: false
      t.string :asa_theme_id
      t.text :asa_theme
      t.string :asa_activity_id
      t.text :asa_activity_name

      t.timestamps
    end

    add_index :action_plan_rows, [ :po_id, :project_name ]
    add_index :action_plan_rows, :project_name
    add_index :action_plan_rows, :to_id

    create_table :action_plan_submissions do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :project_ownership, foreign_key: true
      t.string :po_id, null: false
      t.string :project_name, null: false
      t.text :submission_remark
      t.string :status, default: "pending", null: false
      t.string :current_stage, default: "po", null: false
      t.references :po_approver, foreign_key: { to_table: :employees }
      t.references :coo_approver, foreign_key: { to_table: :employees }
      t.references :director_approver, foreign_key: { to_table: :employees }
      t.datetime :submitted_at, null: false
      t.datetime :po_reviewed_at
      t.datetime :coo_reviewed_at
      t.datetime :director_reviewed_at
      t.text :po_remark
      t.text :coo_remark
      t.text :director_remark

      t.timestamps
    end

    add_index :action_plan_submissions, [ :status, :current_stage, :submitted_at ]
    add_index :action_plan_submissions, [ :po_approver_id, :status, :current_stage ], name: "idx_action_plan_po_pending"
    add_index :action_plan_submissions, [ :coo_approver_id, :status, :current_stage ], name: "idx_action_plan_coo_pending"
    add_index :action_plan_submissions, [ :director_approver_id, :status, :current_stage ], name: "idx_action_plan_director_pending"
  end
end

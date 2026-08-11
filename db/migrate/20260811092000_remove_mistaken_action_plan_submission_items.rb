class RemoveMistakenActionPlanSubmissionItems < ActiveRecord::Migration[8.1]
  def up
    drop_table :action_plan_submission_items, if_exists: true
    change_column_default :action_plan_submissions, :status, from: "draft", to: "pending"
  end

  def down
    change_column_default :action_plan_submissions, :status, from: "pending", to: "draft"

    create_table :action_plan_submission_items do |t|
      t.references :action_plan_submission, null: false, foreign_key: true
      t.references :action_plan_row, null: false, foreign_key: true
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

      t.timestamps
    end

    add_index :action_plan_submission_items,
      [ :action_plan_submission_id, :action_plan_row_id ],
      unique: true,
      name: "idx_action_plan_submission_items_unique"
  end
end

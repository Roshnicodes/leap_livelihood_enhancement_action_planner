class CreatePlanSubmissionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_submission_items do |t|
      t.references :plan_submission, null: false, foreign_key: true
      t.references :bli_activity, null: false, foreign_key: true
      t.decimal :original_fund, precision: 15, scale: 2, default: 0, null: false
      t.decimal :changed_fund, precision: 15, scale: 2, default: 0, null: false
      t.text :remark

      t.timestamps
    end
  end
end

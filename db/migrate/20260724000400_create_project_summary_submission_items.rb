class CreateProjectSummarySubmissionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :project_summary_submission_items do |t|
      t.references :project_summary_submission, null: false, foreign_key: true
      t.string :activity_name, null: false
      t.string :vertical_name, null: false
      t.decimal :total_amount, precision: 15, scale: 2, default: 0, null: false
      t.decimal :apr, precision: 15, scale: 2, default: 0, null: false
      t.decimal :may, precision: 15, scale: 2, default: 0, null: false
      t.decimal :jun, precision: 15, scale: 2, default: 0, null: false
      t.decimal :jul, precision: 15, scale: 2, default: 0, null: false
      t.decimal :aug, precision: 15, scale: 2, default: 0, null: false
      t.decimal :sep, precision: 15, scale: 2, default: 0, null: false
      t.decimal :oct, precision: 15, scale: 2, default: 0, null: false
      t.decimal :nov, precision: 15, scale: 2, default: 0, null: false
      t.decimal :dec, precision: 15, scale: 2, default: 0, null: false
      t.decimal :jan, precision: 15, scale: 2, default: 0, null: false
      t.decimal :feb, precision: 15, scale: 2, default: 0, null: false
      t.decimal :mar, precision: 15, scale: 2, default: 0, null: false
      t.decimal :changed_total, precision: 15, scale: 2, default: 0, null: false
      t.text :remark

      t.timestamps
    end
  end
end

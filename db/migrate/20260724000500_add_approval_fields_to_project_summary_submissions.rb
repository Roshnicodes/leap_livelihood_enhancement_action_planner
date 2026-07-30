class AddApprovalFieldsToProjectSummarySubmissions < ActiveRecord::Migration[8.1]
  def change
    add_reference :project_summary_submissions, :approver, foreign_key: { to_table: :employees }
    add_column :project_summary_submissions, :status, :string, null: false, default: "pending"
    add_column :project_summary_submissions, :approval_remark, :text
    add_column :project_summary_submissions, :reviewed_at, :datetime

    add_index :project_summary_submissions, :status
  end
end

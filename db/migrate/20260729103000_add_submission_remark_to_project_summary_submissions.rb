class AddSubmissionRemarkToProjectSummarySubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :project_summary_submissions, :submission_remark, :text
  end
end

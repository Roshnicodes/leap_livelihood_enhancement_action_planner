class AddProjectNameToProjectSummarySubmissionItems < ActiveRecord::Migration[8.1]
  def change
    add_column :project_summary_submission_items, :project_name, :string
    add_index :project_summary_submission_items, :project_name
  end
end

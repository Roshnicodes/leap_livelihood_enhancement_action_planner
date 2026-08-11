class AddPbAppliedAtToProjectSummarySubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :project_summary_submissions, :pb_applied_at, :datetime
  end
end

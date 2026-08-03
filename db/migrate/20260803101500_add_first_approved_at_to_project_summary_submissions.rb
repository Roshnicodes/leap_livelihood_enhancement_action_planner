class AddFirstApprovedAtToProjectSummarySubmissions < ActiveRecord::Migration[8.1]
  def up
    add_column :project_summary_submissions, :first_approved_at, :datetime

    execute <<~SQL.squish
      UPDATE project_summary_submissions
      SET first_approved_at = updated_at
      WHERE first_approver_id IS NOT NULL
        AND first_approved_at IS NULL
    SQL
  end

  def down
    remove_column :project_summary_submissions, :first_approved_at
  end
end

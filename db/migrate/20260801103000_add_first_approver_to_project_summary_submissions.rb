class AddFirstApproverToProjectSummarySubmissions < ActiveRecord::Migration[8.1]
  def up
    add_reference :project_summary_submissions, :first_approver, foreign_key: { to_table: :employees }

    first_approver = Employee.find_by(employee_code: ProjectSummarySubmission::FIRST_APPROVER_EMPLOYEE_CODE)
    final_approver = Employee.find_by(employee_code: ProjectSummarySubmission::FINAL_APPROVER_EMPLOYEE_CODE)
    return unless first_approver && final_approver

    ProjectSummarySubmission.where(approver: final_approver, first_approver_id: nil, status: %w[pending approved])
      .update_all(first_approver_id: first_approver.id)
  end

  def down
    remove_reference :project_summary_submissions, :first_approver, foreign_key: { to_table: :employees }
  end
end

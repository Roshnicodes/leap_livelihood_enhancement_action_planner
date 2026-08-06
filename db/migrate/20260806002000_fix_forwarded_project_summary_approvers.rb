class FixForwardedProjectSummaryApprovers < ActiveRecord::Migration[7.2]
  class MigrationProjectSummarySubmission < ActiveRecord::Base
    self.table_name = "project_summary_submissions"
  end

  class MigrationEmployee < ActiveRecord::Base
    self.table_name = "employees"
  end

  def up
    final_approver = MigrationEmployee.find_by(employee_code: "002")
    return if final_approver.blank?

    MigrationProjectSummarySubmission
      .where(status: "pending")
      .where.not(first_approver_id: nil)
      .update_all(approver_id: final_approver.id, updated_at: Time.current)
  end

  def down
    # Historical approver correction is not safely reversible.
  end
end

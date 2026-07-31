class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :bli_activities, [:employee_id, :project_name, :vertical_name],
      name: "index_bli_activities_on_employee_project_vertical"
    add_index :bli_activities, [:employee_id, :vertical_name, :project_name, :activity_name],
      name: "index_bli_activities_on_employee_vertical_project_activity"
    add_index :bli_activities, [:vertical_name, :project_name],
      name: "index_bli_activities_on_vertical_project"

    add_index :plan_submissions, [:employee_id, :mode, :filter_name, :submitted_at],
      name: "index_plan_submissions_lookup_latest"
    add_index :plan_submission_items, [:plan_submission_id, :bli_activity_id],
      name: "index_plan_submission_items_on_submission_activity"

    add_index :project_summary_submissions, [:employee_id, :status, :submitted_at],
      name: "index_project_summary_submissions_on_employee_status_time"
    add_index :project_summary_submissions, [:approver_id, :status, :submitted_at],
      name: "index_project_summary_submissions_on_approver_status_time"

    add_index :project_summary_submission_items, [:project_summary_submission_id, :project_name],
      name: "index_project_summary_items_on_submission_project"
    add_index :project_summary_submission_items, [:vertical_name, :project_name],
      name: "index_project_summary_items_on_vertical_project"
    add_index :project_summary_submission_items, [:project_name, :activity_name, :vertical_name],
      name: "index_project_summary_items_on_project_activity_vertical"
  end
end

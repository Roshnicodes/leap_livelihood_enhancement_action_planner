class AddSecondaryPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :action_plan_rows, [ :import_flag, :po_id, :id ],
      name: "idx_action_plan_rows_active_po_order",
      if_not_exists: true
    add_index :action_plan_rows, [ :import_flag, :user_id, :project_name, :id ],
      name: "idx_action_plan_rows_active_fco_project_order",
      if_not_exists: true
    add_index :action_plan_rows, [ :import_flag, :user_id, :to_id, :project_name, :asa_theme_id, :asa_activity_id, :activity_id, :id ],
      name: "idx_action_plan_rows_active_achievement_order",
      if_not_exists: true
    add_index :action_plan_rows, [ :import_flag, :project_name, :theme ],
      name: "idx_action_plan_rows_active_project_theme",
      if_not_exists: true

    add_index :action_plan_fco_mappings, [ :employee_id, :fco_name, :fco_id ],
      name: "idx_action_plan_fco_mappings_employee_name",
      if_not_exists: true
    add_index :action_plan_vertical_mappings, [ :employee_code, :state_code, :asa_theme_id ],
      name: "idx_action_plan_vertical_mappings_employee_code_lookup",
      if_not_exists: true

    add_index :bli_activities, [ :employee_id, :project_name, :bli_code, :name, :activity_name, :vertical_name ],
      name: "idx_bli_activities_employee_budget_order",
      if_not_exists: true
    add_index :bli_activities, [ :project_name, :bli_code, :name, :activity_name, :vertical_name ],
      name: "idx_bli_activities_project_budget_order",
      if_not_exists: true
    add_index :bli_activities, [ :employee_id, :project_name, :vertical_name, :activity_name, :bli_code, :id ],
      name: "idx_bli_activities_employee_export_order",
      if_not_exists: true
    add_index :bli_activities, [ :responsible_user_name ],
      name: "idx_bli_activities_responsible_user_name",
      if_not_exists: true

    add_index :budget_utilizations, [ :status, :project_name, :month, :bli_code ],
      name: "idx_budget_utilizations_report_lookup",
      if_not_exists: true
    add_index :budget_utilizations, [ :submitted_by_id, :status, :submitted_at ],
      name: "idx_budget_utilizations_submitter_status_time",
      if_not_exists: true

    add_index :project_summary_submissions, [ :first_approver_id, :status, :submitted_at ],
      name: "idx_project_summary_first_approver_status_time",
      if_not_exists: true
    add_index :project_summary_submissions, [ :status, :submitted_at ],
      name: "idx_project_summary_status_time",
      if_not_exists: true
    add_index :project_summary_submission_items, [ :project_summary_submission_id, :vertical_name, :activity_name ],
      name: "idx_project_summary_items_submission_vertical_activity",
      if_not_exists: true

    add_index :plan_submissions, [ :mode, :filter_name, :submitted_at ],
      name: "idx_plan_submissions_mode_filter_time",
      if_not_exists: true

    add_index :pis_document_types, [ :active, :name ],
      name: "idx_pis_document_types_active_name",
      if_not_exists: true
    add_index :donor_report_types, [ :active, :name ],
      name: "idx_donor_report_types_active_name",
      if_not_exists: true
    add_index :fund_report_types, [ :active, :name ],
      name: "idx_fund_report_types_active_name",
      if_not_exists: true

    add_index :pis_report_documents, [ :created_at, :id ],
      name: "idx_pis_documents_recent_order",
      if_not_exists: true
    add_index :donor_report_uploads, [ :created_at, :id ],
      name: "idx_donor_uploads_recent_order",
      if_not_exists: true
    add_index :fund_report_uploads, [ :created_at, :id ],
      name: "idx_fund_uploads_recent_order",
      if_not_exists: true

    add_index :employees, [ :active, :name ],
      name: "idx_employees_active_name",
      if_not_exists: true
  end
end

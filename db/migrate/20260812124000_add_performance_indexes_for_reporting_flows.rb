class AddPerformanceIndexesForReportingFlows < ActiveRecord::Migration[8.1]
  def change
    add_index :bli_activities, [ :project_name, :vertical_name, :bli_code, :id ],
      name: "idx_bli_activities_project_vertical_code_id",
      if_not_exists: true
    add_index :bli_activities, [ :project_name, :activity_name, :vertical_name ],
      name: "idx_bli_activities_project_activity_vertical",
      if_not_exists: true
    add_index :bli_activities, [ :project_name, :bli_code ],
      name: "idx_bli_activities_project_code",
      if_not_exists: true

    add_index :action_plan_rows, [ :import_flag, :project_name, :id ],
      name: "idx_action_plan_rows_active_project_order",
      if_not_exists: true
    add_index :action_plan_rows, [ :import_flag, :po_id, :project_name, :id ],
      name: "idx_action_plan_rows_active_po_project_order",
      if_not_exists: true
    add_index :action_plan_rows, [ :import_flag, :user_id, :to_id, :project_name, :id ],
      name: "idx_action_plan_rows_active_fco_to_project_order",
      if_not_exists: true

    add_index :budget_utilizations, [ :status, :month, :project_name ],
      name: "idx_budget_utilizations_status_month_project",
      if_not_exists: true
    add_index :budget_utilizations, [ :project_name, :status, :updated_at ],
      name: "idx_budget_utilizations_project_status_updated",
      if_not_exists: true

    add_index :action_plan_submissions, [ :project_name, :plan_type, :submitted_at ],
      name: "idx_action_plan_submissions_project_type_time",
      if_not_exists: true
    add_index :achievement_submissions, [ :project_name, :month, :submitted_at ],
      name: "idx_achievement_submissions_project_month_time",
      if_not_exists: true

    add_index :pis_report_documents, [ :project_name, :financial_year, :pis_document_type_id, :created_at ],
      name: "idx_pis_documents_filters_recent",
      if_not_exists: true
    add_index :donor_report_uploads, [ :project_name, :frequency, :donor_report_type_id, :created_at ],
      name: "idx_donor_uploads_filters_recent",
      if_not_exists: true
    add_index :fund_report_uploads, [ :project_name, :fund_report_type_id, :created_at ],
      name: "idx_fund_uploads_filters_recent",
      if_not_exists: true

    add_index :pb_import_files, [ :file_kind, :status, :financial_year, :imported_at ],
      name: "idx_pb_import_files_kind_status_year_time",
      if_not_exists: true
    add_index :action_plan_import_files, [ :import_type, :status, :financial_year, :imported_at ],
      name: "idx_action_plan_import_files_type_status_year_time",
      if_not_exists: true

    add_index :employees, "lower(email)",
      name: "idx_employees_lower_email",
      if_not_exists: true
    add_index :employees, "lower(name)",
      name: "idx_employees_lower_name",
      if_not_exists: true
    add_index :project_ownerships, "lower(email_id)",
      name: "idx_project_ownerships_lower_email_id",
      if_not_exists: true
    add_index :project_ownerships, "lower(po_name)",
      name: "idx_project_ownerships_lower_po_name",
      if_not_exists: true
  end
end

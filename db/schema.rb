# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_13_113000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "achievement_entry_details", force: :cascade do |t|
    t.bigint "action_plan_row_id", null: false
    t.datetime "created_at", null: false
    t.string "month", null: false
    t.text "remark"
    t.datetime "updated_at", null: false
    t.index ["action_plan_row_id", "month"], name: "idx_achievement_entry_details_row_month", unique: true
    t.index ["action_plan_row_id"], name: "index_achievement_entry_details_on_action_plan_row_id"
  end

  create_table "achievement_submission_rows", force: :cascade do |t|
    t.bigint "achievement_submission_id", null: false
    t.integer "achievement_value", default: 0, null: false
    t.bigint "action_plan_row_id", null: false
    t.datetime "created_at", null: false
    t.string "month", null: false
    t.integer "target_value", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["achievement_submission_id"], name: "index_achievement_submission_rows_on_achievement_submission_id"
    t.index ["action_plan_row_id", "month", "achievement_submission_id"], name: "idx_achievement_submission_rows_unique", unique: true
    t.index ["action_plan_row_id"], name: "index_achievement_submission_rows_on_action_plan_row_id"
    t.index ["month", "action_plan_row_id"], name: "idx_achievement_submission_rows_month_row"
  end

  create_table "achievement_submissions", force: :cascade do |t|
    t.string "asa_theme_id", null: false
    t.bigint "coo_approver_id"
    t.text "coo_remark"
    t.datetime "coo_reviewed_at"
    t.datetime "created_at", null: false
    t.string "current_stage", default: "vertical", null: false
    t.bigint "director_approver_id"
    t.text "director_remark"
    t.datetime "director_reviewed_at"
    t.bigint "employee_id", null: false
    t.string "fco_id", null: false
    t.string "fco_name", null: false
    t.string "month", null: false
    t.bigint "po_approver_id"
    t.string "po_id", null: false
    t.text "po_remark"
    t.datetime "po_reviewed_at"
    t.string "project_name", null: false
    t.string "state_code"
    t.string "status", default: "pending", null: false
    t.text "submission_remark"
    t.datetime "submitted_at", null: false
    t.string "to_id", null: false
    t.string "to_name"
    t.datetime "updated_at", null: false
    t.bigint "vertical_approver_id"
    t.text "vertical_remark"
    t.datetime "vertical_reviewed_at"
    t.index ["coo_approver_id", "status", "current_stage"], name: "idx_achievement_coo_pending"
    t.index ["coo_approver_id"], name: "index_achievement_submissions_on_coo_approver_id"
    t.index ["director_approver_id", "status", "current_stage"], name: "idx_achievement_director_pending"
    t.index ["director_approver_id"], name: "index_achievement_submissions_on_director_approver_id"
    t.index ["employee_id", "project_name", "to_id", "month"], name: "idx_achievement_submission_employee_scope"
    t.index ["employee_id"], name: "index_achievement_submissions_on_employee_id"
    t.index ["po_approver_id", "status", "current_stage"], name: "idx_achievement_po_pending"
    t.index ["po_approver_id"], name: "index_achievement_submissions_on_po_approver_id"
    t.index ["project_name", "month", "submitted_at"], name: "idx_achievement_submissions_project_month_time"
    t.index ["status", "current_stage", "submitted_at"], name: "idx_on_status_current_stage_submitted_at_bd6c858085"
    t.index ["to_id", "project_name", "month", "status"], name: "idx_achievement_submissions_scope_status"
    t.index ["vertical_approver_id", "status", "current_stage"], name: "idx_achievement_vertical_pending"
    t.index ["vertical_approver_id"], name: "index_achievement_submissions_on_vertical_approver_id"
  end

  create_table "action_plan_fco_mappings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "employee_code", null: false
    t.bigint "employee_id", null: false
    t.string "fco_id", null: false
    t.string "fco_name", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_code"], name: "index_action_plan_fco_mappings_on_employee_code"
    t.index ["employee_id", "fco_id"], name: "idx_action_plan_fco_employee_fco", unique: true
    t.index ["employee_id", "fco_name", "fco_id"], name: "idx_action_plan_fco_mappings_employee_name"
    t.index ["employee_id"], name: "index_action_plan_fco_mappings_on_employee_id"
    t.index ["fco_id"], name: "index_action_plan_fco_mappings_on_fco_id"
  end

  create_table "action_plan_import_files", force: :cascade do |t|
    t.integer "byte_size", default: 0, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "financial_year", null: false
    t.string "import_type", null: false
    t.datetime "imported_at", null: false
    t.string "original_filename", null: false
    t.integer "row_count"
    t.string "status", default: "saved", null: false
    t.string "storage_path", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["financial_year"], name: "index_action_plan_import_files_on_financial_year"
    t.index ["import_type", "status", "financial_year", "imported_at"], name: "idx_action_plan_import_files_type_status_year_time"
    t.index ["import_type"], name: "index_action_plan_import_files_on_import_type"
    t.index ["imported_at"], name: "index_action_plan_import_files_on_imported_at"
    t.index ["status"], name: "index_action_plan_import_files_on_status"
    t.index ["storage_path"], name: "index_action_plan_import_files_on_storage_path", unique: true
    t.index ["uploaded_by_id"], name: "index_action_plan_import_files_on_uploaded_by_id"
  end

  create_table "action_plan_rows", force: :cascade do |t|
    t.text "a_remark"
    t.text "activity"
    t.string "activity_id"
    t.integer "apr", default: 0, null: false
    t.integer "apr_t", default: 0, null: false
    t.string "asa_activity_id"
    t.text "asa_activity_name"
    t.text "asa_theme"
    t.string "asa_theme_id"
    t.integer "aug", default: 0, null: false
    t.integer "aug_t", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "dec", default: 0, null: false
    t.integer "dec_t", default: 0, null: false
    t.integer "feb", default: 0, null: false
    t.integer "feb_t", default: 0, null: false
    t.string "id_new"
    t.integer "import_flag", default: 0, null: false
    t.datetime "imported_at"
    t.integer "jan", default: 0, null: false
    t.integer "jan_t", default: 0, null: false
    t.integer "jul", default: 0, null: false
    t.integer "jul_t", default: 0, null: false
    t.integer "jun", default: 0, null: false
    t.integer "jun_t", default: 0, null: false
    t.integer "mar", default: 0, null: false
    t.integer "mar_t", default: 0, null: false
    t.integer "may", default: 0, null: false
    t.integer "may_t", default: 0, null: false
    t.integer "nov", default: 0, null: false
    t.integer "nov_t", default: 0, null: false
    t.integer "oct", default: 0, null: false
    t.integer "oct_t", default: 0, null: false
    t.integer "original_apr", default: 0, null: false
    t.integer "original_aug", default: 0, null: false
    t.integer "original_dec", default: 0, null: false
    t.integer "original_feb", default: 0, null: false
    t.integer "original_jan", default: 0, null: false
    t.integer "original_jul", default: 0, null: false
    t.integer "original_jun", default: 0, null: false
    t.integer "original_mar", default: 0, null: false
    t.integer "original_may", default: 0, null: false
    t.integer "original_nov", default: 0, null: false
    t.integer "original_oct", default: 0, null: false
    t.integer "original_sep", default: 0, null: false
    t.integer "planned_total", default: 0, null: false
    t.string "po_id", null: false
    t.string "project_id"
    t.string "project_name", null: false
    t.string "project_owner"
    t.string "responsibel"
    t.integer "sep", default: 0, null: false
    t.integer "sep_t", default: 0, null: false
    t.string "statte"
    t.text "theme"
    t.string "theme_id"
    t.string "to_id"
    t.string "to_name"
    t.string "unit_type"
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.string "user_name"
    t.index ["id_new"], name: "index_action_plan_rows_on_id_new"
    t.index ["import_flag", "po_id", "id"], name: "idx_action_plan_rows_active_po_order"
    t.index ["import_flag", "po_id", "project_name", "id"], name: "idx_action_plan_rows_active_po_project_order"
    t.index ["import_flag", "project_name", "id"], name: "idx_action_plan_rows_active_project_order"
    t.index ["import_flag", "project_name", "theme"], name: "idx_action_plan_rows_active_project_theme"
    t.index ["import_flag", "to_id", "project_name"], name: "idx_action_plan_rows_active_to_project"
    t.index ["import_flag", "user_id", "project_name", "id"], name: "idx_action_plan_rows_active_fco_project_order"
    t.index ["import_flag", "user_id", "to_id", "project_name", "asa_theme_id", "asa_activity_id", "activity_id", "id"], name: "idx_action_plan_rows_active_achievement_order"
    t.index ["import_flag", "user_id", "to_id", "project_name", "id"], name: "idx_action_plan_rows_active_fco_to_project_order"
    t.index ["import_flag", "user_id", "to_id", "project_name"], name: "idx_action_plan_rows_active_user_to_project"
    t.index ["import_flag", "user_id", "to_id"], name: "idx_action_plan_rows_active_user_to"
    t.index ["import_flag", "user_id"], name: "idx_action_plan_rows_active_user"
    t.index ["import_flag"], name: "index_action_plan_rows_on_import_flag"
    t.index ["imported_at"], name: "index_action_plan_rows_on_imported_at"
    t.index ["po_id", "project_name"], name: "index_action_plan_rows_on_po_id_and_project_name"
    t.index ["project_name"], name: "index_action_plan_rows_on_project_name"
    t.index ["statte", "asa_theme_id"], name: "idx_action_plan_rows_state_theme"
    t.index ["to_id"], name: "index_action_plan_rows_on_to_id"
    t.index ["user_id"], name: "index_action_plan_rows_on_user_id"
  end

  create_table "action_plan_submissions", force: :cascade do |t|
    t.bigint "coo_approver_id"
    t.text "coo_remark"
    t.datetime "coo_reviewed_at"
    t.datetime "created_at", null: false
    t.string "current_stage", default: "po", null: false
    t.bigint "director_approver_id"
    t.text "director_remark"
    t.datetime "director_reviewed_at"
    t.bigint "employee_id", null: false
    t.string "plan_type", default: "project", null: false
    t.bigint "po_approver_id"
    t.string "po_id", null: false
    t.text "po_remark"
    t.datetime "po_reviewed_at"
    t.string "project_name", null: false
    t.bigint "project_ownership_id"
    t.string "status", default: "pending", null: false
    t.text "submission_remark"
    t.datetime "submitted_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coo_approver_id", "status", "current_stage"], name: "idx_action_plan_coo_pending"
    t.index ["coo_approver_id"], name: "index_action_plan_submissions_on_coo_approver_id"
    t.index ["director_approver_id", "status", "current_stage"], name: "idx_action_plan_director_pending"
    t.index ["director_approver_id"], name: "index_action_plan_submissions_on_director_approver_id"
    t.index ["employee_id", "plan_type", "project_name", "submitted_at"], name: "idx_action_plan_submissions_employee_type_project"
    t.index ["employee_id"], name: "index_action_plan_submissions_on_employee_id"
    t.index ["plan_type", "status", "current_stage"], name: "idx_action_plan_submissions_type_stage"
    t.index ["po_approver_id", "status", "current_stage"], name: "idx_action_plan_po_pending"
    t.index ["po_approver_id"], name: "index_action_plan_submissions_on_po_approver_id"
    t.index ["project_name", "plan_type", "submitted_at"], name: "idx_action_plan_submissions_project_type_time"
    t.index ["project_ownership_id"], name: "index_action_plan_submissions_on_project_ownership_id"
    t.index ["status", "current_stage", "submitted_at"], name: "idx_on_status_current_stage_submitted_at_6caf8268b6"
  end

  create_table "action_plan_vertical_mappings", force: :cascade do |t|
    t.text "asa_theme"
    t.string "asa_theme_id", null: false
    t.datetime "created_at", null: false
    t.string "employee_code", null: false
    t.bigint "employee_id"
    t.string "state_code", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_code", "state_code", "asa_theme_id"], name: "idx_action_plan_vertical_mappings_employee_code_lookup"
    t.index ["employee_code", "state_code", "asa_theme_id"], name: "idx_action_plan_vertical_mappings_unique", unique: true
    t.index ["employee_id", "state_code", "asa_theme_id"], name: "idx_action_plan_vertical_mappings_employee_lookup"
    t.index ["employee_id"], name: "index_action_plan_vertical_mappings_on_employee_id"
    t.index ["state_code", "asa_theme_id"], name: "idx_action_plan_vertical_mappings_state_theme"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bli_activities", force: :cascade do |t|
    t.string "activity_name"
    t.decimal "allocated_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.date "allocating_date"
    t.decimal "approved_pdo_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "approved_pdo_count", default: 0, null: false
    t.decimal "approved_rfp_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "approved_rfp_count", default: 0, null: false
    t.decimal "approved_utilised_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.string "bli_code"
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.string "financial_year"
    t.string "name"
    t.string "office_name"
    t.string "parent_activity"
    t.decimal "pending_pdo_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "pending_pdo_count", default: 0, null: false
    t.decimal "pending_rfp_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "pending_rfp_count", default: 0, null: false
    t.string "project_name"
    t.decimal "remaining_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.string "responsible_user_name"
    t.string "stakeholder_name"
    t.decimal "total_pdo_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "total_pdo_count", default: 0, null: false
    t.decimal "total_rfp_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "total_rfp_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "utilised_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.string "vertical_name"
    t.index ["employee_id", "project_name", "bli_code", "name", "activity_name", "vertical_name"], name: "idx_bli_activities_employee_budget_order"
    t.index ["employee_id", "project_name", "vertical_name", "activity_name", "bli_code", "id"], name: "idx_bli_activities_employee_export_order"
    t.index ["employee_id", "project_name", "vertical_name"], name: "index_bli_activities_on_employee_project_vertical"
    t.index ["employee_id", "vertical_name", "project_name", "activity_name"], name: "index_bli_activities_on_employee_vertical_project_activity"
    t.index ["employee_id"], name: "index_bli_activities_on_employee_id"
    t.index ["financial_year"], name: "index_bli_activities_on_financial_year"
    t.index ["project_name", "activity_name", "vertical_name"], name: "idx_bli_activities_project_activity_vertical"
    t.index ["project_name", "bli_code", "name", "activity_name", "vertical_name"], name: "idx_bli_activities_project_budget_order"
    t.index ["project_name", "bli_code"], name: "idx_bli_activities_project_code"
    t.index ["project_name", "vertical_name", "bli_code", "id"], name: "idx_bli_activities_project_vertical_code_id"
    t.index ["project_name"], name: "index_bli_activities_on_project_name"
    t.index ["responsible_user_name"], name: "idx_bli_activities_responsible_user_name"
    t.index ["vertical_name", "project_name"], name: "index_bli_activities_on_vertical_project"
    t.index ["vertical_name"], name: "index_bli_activities_on_vertical_name"
  end

  create_table "budget_utilizations", force: :cascade do |t|
    t.string "activity_name", null: false
    t.string "bli_code"
    t.datetime "created_at", null: false
    t.string "month", null: false
    t.decimal "planned_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.string "project_name", null: false
    t.text "remark"
    t.string "status", default: "draft", null: false
    t.datetime "submitted_at"
    t.bigint "submitted_by_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.decimal "utilized_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.string "vertical_name", null: false
    t.index ["month"], name: "index_budget_utilizations_on_month"
    t.index ["project_name", "bli_code", "month"], name: "idx_budget_utilizations_unique_scope", unique: true
    t.index ["project_name", "month", "status"], name: "index_budget_utilizations_on_project_name_and_month_and_status"
    t.index ["project_name", "month"], name: "index_budget_utilizations_on_project_name_and_month"
    t.index ["project_name", "status", "updated_at"], name: "idx_budget_utilizations_project_status_updated"
    t.index ["status", "month", "project_name"], name: "idx_budget_utilizations_status_month_project"
    t.index ["status", "project_name", "month", "bli_code"], name: "idx_budget_utilizations_report_lookup"
    t.index ["status"], name: "index_budget_utilizations_on_status"
    t.index ["submitted_by_id", "status", "submitted_at"], name: "idx_budget_utilizations_submitter_status_time"
    t.index ["submitted_by_id"], name: "index_budget_utilizations_on_submitted_by_id"
    t.index ["updated_by_id"], name: "index_budget_utilizations_on_updated_by_id"
  end

  create_table "donor_report_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "name"], name: "idx_donor_report_types_active_name"
    t.index ["active"], name: "index_donor_report_types_on_active"
    t.index ["name"], name: "index_donor_report_types_on_name", unique: true
  end

  create_table "donor_report_uploads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "donor_report_type_id", null: false
    t.string "financial_year", default: "2026-2027", null: false
    t.string "frequency", null: false
    t.string "project_name", null: false
    t.date "submission_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["created_at", "id"], name: "idx_donor_uploads_recent_order"
    t.index ["donor_report_type_id"], name: "index_donor_report_uploads_on_donor_report_type_id"
    t.index ["frequency"], name: "index_donor_report_uploads_on_frequency"
    t.index ["project_name", "financial_year", "donor_report_type_id", "frequency", "created_at"], name: "idx_donor_uploads_project_year_type_frequency_recent"
    t.index ["project_name", "frequency", "donor_report_type_id", "created_at"], name: "idx_donor_uploads_filters_recent"
    t.index ["project_name"], name: "index_donor_report_uploads_on_project_name"
    t.index ["submission_date"], name: "index_donor_report_uploads_on_submission_date"
    t.index ["uploaded_by_id"], name: "index_donor_report_uploads_on_uploaded_by_id"
  end

  create_table "employee_vertical_mappings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "vertical_percent_id", null: false
    t.index ["employee_id", "vertical_percent_id"], name: "index_employee_vertical_mappings_unique", unique: true
    t.index ["employee_id"], name: "index_employee_vertical_mappings_on_employee_id"
    t.index ["vertical_percent_id"], name: "index_employee_vertical_mappings_on_vertical_percent_id"
  end

  create_table "employees", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "branch"
    t.datetime "created_at", null: false
    t.string "department"
    t.string "designation"
    t.string "email"
    t.string "employee_code", null: false
    t.string "functional_responsibility"
    t.string "mobile_number"
    t.string "name", null: false
    t.string "office_name"
    t.string "primary_project"
    t.string "primary_vertical"
    t.string "sub_branch"
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "idx_employees_lower_email"
    t.index "lower((name)::text)", name: "idx_employees_lower_name"
    t.index ["active", "name"], name: "idx_employees_active_name"
    t.index ["department"], name: "index_employees_on_department"
    t.index ["email"], name: "index_employees_on_email"
    t.index ["employee_code"], name: "index_employees_on_employee_code", unique: true
    t.index ["name"], name: "index_employees_on_name"
  end

  create_table "fund_report_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "name"], name: "idx_fund_report_types_active_name"
    t.index ["active"], name: "index_fund_report_types_on_active"
    t.index ["name"], name: "index_fund_report_types_on_name", unique: true
  end

  create_table "fund_report_uploads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "financial_year", default: "2026-2027", null: false
    t.bigint "fund_report_type_id", null: false
    t.string "project_name", null: false
    t.decimal "submission_letter_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.date "submission_letter_date", null: false
    t.decimal "submission_receipt_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.date "submission_receipt_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["created_at", "id"], name: "idx_fund_uploads_recent_order"
    t.index ["fund_report_type_id"], name: "index_fund_report_uploads_on_fund_report_type_id"
    t.index ["project_name", "financial_year", "fund_report_type_id", "created_at"], name: "idx_fund_uploads_project_year_type_recent"
    t.index ["project_name", "fund_report_type_id", "created_at"], name: "idx_fund_uploads_filters_recent"
    t.index ["project_name"], name: "index_fund_report_uploads_on_project_name"
    t.index ["submission_letter_date"], name: "index_fund_report_uploads_on_submission_letter_date"
    t.index ["submission_receipt_date"], name: "index_fund_report_uploads_on_submission_receipt_date"
    t.index ["uploaded_by_id"], name: "index_fund_report_uploads_on_uploaded_by_id"
  end

  create_table "parent_activity_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.string "source_parent_activity", null: false
    t.datetime "updated_at", null: false
    t.bigint "vertical_percent_id", null: false
    t.index ["employee_id", "vertical_percent_id"], name: "index_parent_activity_assignments_on_employee_vertical"
    t.index ["employee_id"], name: "index_parent_activity_assignments_on_employee_id"
    t.index ["source_parent_activity"], name: "index_parent_activity_assignments_on_source", unique: true
    t.index ["vertical_percent_id"], name: "index_parent_activity_assignments_on_vertical_percent_id"
  end

  create_table "pb_import_files", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.integer "byte_size", default: 0, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "file_kind", default: "source", null: false
    t.string "financial_year", null: false
    t.datetime "imported_at", null: false
    t.string "original_filename", null: false
    t.integer "row_count"
    t.string "status", default: "saved", null: false
    t.string "storage_path", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["approved_by_id"], name: "index_pb_import_files_on_approved_by_id"
    t.index ["file_kind", "status", "financial_year", "imported_at"], name: "idx_pb_import_files_kind_status_year_time"
    t.index ["file_kind"], name: "index_pb_import_files_on_file_kind"
    t.index ["financial_year"], name: "index_pb_import_files_on_financial_year"
    t.index ["imported_at"], name: "index_pb_import_files_on_imported_at"
    t.index ["status"], name: "index_pb_import_files_on_status"
    t.index ["storage_path"], name: "index_pb_import_files_on_storage_path", unique: true
    t.index ["uploaded_by_id"], name: "index_pb_import_files_on_uploaded_by_id"
  end

  create_table "pis_document_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "name"], name: "idx_pis_document_types_active_name"
    t.index ["active"], name: "index_pis_document_types_on_active"
    t.index ["name"], name: "index_pis_document_types_on_name", unique: true
  end

  create_table "pis_report_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "financial_year", null: false
    t.bigint "pis_document_type_id", null: false
    t.string "project_name", null: false
    t.date "submission_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["created_at", "id"], name: "idx_pis_documents_recent_order"
    t.index ["financial_year"], name: "index_pis_report_documents_on_financial_year"
    t.index ["pis_document_type_id"], name: "index_pis_report_documents_on_pis_document_type_id"
    t.index ["project_name", "financial_year", "pis_document_type_id", "created_at"], name: "idx_pis_documents_filters_recent"
    t.index ["project_name"], name: "index_pis_report_documents_on_project_name"
    t.index ["submission_date"], name: "index_pis_report_documents_on_submission_date"
    t.index ["uploaded_by_id"], name: "index_pis_report_documents_on_uploaded_by_id"
  end

  create_table "plan_submission_items", force: :cascade do |t|
    t.bigint "bli_activity_id", null: false
    t.decimal "changed_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "original_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "plan_submission_id", null: false
    t.text "remark"
    t.datetime "updated_at", null: false
    t.index ["bli_activity_id"], name: "index_plan_submission_items_on_bli_activity_id"
    t.index ["plan_submission_id", "bli_activity_id"], name: "index_plan_submission_items_on_submission_activity"
    t.index ["plan_submission_id"], name: "index_plan_submission_items_on_plan_submission_id"
  end

  create_table "plan_submissions", force: :cascade do |t|
    t.decimal "changed_total", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.string "filter_name", null: false
    t.string "mode", null: false
    t.decimal "original_total", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "submitted_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "mode", "filter_name", "submitted_at"], name: "index_plan_submissions_lookup_latest"
    t.index ["employee_id"], name: "index_plan_submissions_on_employee_id"
    t.index ["mode", "filter_name", "submitted_at"], name: "idx_plan_submissions_mode_filter_time"
    t.index ["mode"], name: "index_plan_submissions_on_mode"
    t.index ["submitted_at"], name: "index_plan_submissions_on_submitted_at"
  end

  create_table "project_information_sheets", force: :cascade do |t|
    t.string "annexure"
    t.string "category"
    t.datetime "created_at", null: false
    t.string "donor"
    t.string "donor_reporting_officer"
    t.date "end_date"
    t.string "fco_name"
    t.string "financial"
    t.string "households_to_be_covered"
    t.string "physical"
    t.string "po"
    t.string "project_area_map"
    t.string "project_id", null: false
    t.text "project_location"
    t.text "project_objectives"
    t.text "project_period"
    t.string "project_title"
    t.string "reporting_system"
    t.date "start_date"
    t.decimal "total", precision: 18, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.jsonb "yearly_amounts", default: {}, null: false
    t.index ["donor"], name: "index_project_information_sheets_on_donor"
    t.index ["project_id"], name: "index_project_information_sheets_on_project_id", unique: true
    t.index ["project_title"], name: "index_project_information_sheets_on_project_title"
    t.index ["updated_at"], name: "index_project_information_sheets_on_updated_at"
    t.index ["uploaded_by_id"], name: "index_project_information_sheets_on_uploaded_by_id"
  end

  create_table "project_ownerships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_id"
    t.string "po_id", null: false
    t.string "po_name"
    t.string "project_name", null: false
    t.string "project_owner_id"
    t.datetime "updated_at", null: false
    t.index "lower((email_id)::text)", name: "idx_project_ownerships_lower_email_id"
    t.index "lower((po_name)::text)", name: "idx_project_ownerships_lower_po_name"
    t.index ["email_id"], name: "index_project_ownerships_on_email_id"
    t.index ["po_id", "project_name"], name: "index_project_ownerships_on_po_id_and_project_name", unique: true
    t.index ["project_name"], name: "index_project_ownerships_on_project_name"
    t.index ["project_owner_id"], name: "index_project_ownerships_on_project_owner_id"
  end

  create_table "project_summary_submission_items", force: :cascade do |t|
    t.string "activity_name", null: false
    t.decimal "apr", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "aug", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "changed_total", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "dec", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "feb", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "jan", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "jul", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "jun", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "mar", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "may", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "nov", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "oct", precision: 15, scale: 2, default: "0.0", null: false
    t.string "project_name"
    t.bigint "project_summary_submission_id", null: false
    t.text "remark"
    t.decimal "sep", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.string "vertical_name", null: false
    t.index ["project_name", "activity_name", "vertical_name"], name: "index_project_summary_items_on_project_activity_vertical"
    t.index ["project_name"], name: "index_project_summary_submission_items_on_project_name"
    t.index ["project_summary_submission_id", "project_name"], name: "index_project_summary_items_on_submission_project"
    t.index ["project_summary_submission_id", "vertical_name", "activity_name"], name: "idx_project_summary_items_submission_vertical_activity"
    t.index ["project_summary_submission_id"], name: "idx_on_project_summary_submission_id_82944b0850"
    t.index ["vertical_name", "project_name"], name: "index_project_summary_items_on_vertical_project"
  end

  create_table "project_summary_submissions", force: :cascade do |t|
    t.text "approval_remark"
    t.bigint "approver_id"
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.datetime "first_approved_at"
    t.bigint "first_approver_id"
    t.datetime "pb_applied_at"
    t.datetime "reviewed_at"
    t.string "status", default: "pending", null: false
    t.text "submission_remark"
    t.datetime "submitted_at", null: false
    t.decimal "total_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["approver_id", "status", "submitted_at"], name: "index_project_summary_submissions_on_approver_status_time"
    t.index ["approver_id"], name: "index_project_summary_submissions_on_approver_id"
    t.index ["employee_id", "status", "submitted_at"], name: "index_project_summary_submissions_on_employee_status_time"
    t.index ["employee_id"], name: "index_project_summary_submissions_on_employee_id"
    t.index ["first_approver_id", "status", "submitted_at"], name: "idx_project_summary_first_approver_status_time"
    t.index ["first_approver_id"], name: "index_project_summary_submissions_on_first_approver_id"
    t.index ["status", "submitted_at"], name: "idx_project_summary_status_time"
    t.index ["status"], name: "index_project_summary_submissions_on_status"
    t.index ["submitted_at"], name: "index_project_summary_submissions_on_submitted_at"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employee_id"
    t.string "login", null: false
    t.string "password_hash", null: false
    t.string "password_salt", null: false
    t.string "role", default: "user", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_users_on_employee_id"
    t.index ["login"], name: "index_users_on_login", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "vertical_percents", force: :cascade do |t|
    t.decimal "apr", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "aug", precision: 10, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "dec", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "feb", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "jan", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "jul", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "jun", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "mar", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "may", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "nov", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "oct", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "sep", precision: 10, scale: 6, default: "0.0", null: false
    t.decimal "total", precision: 10, scale: 6, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.string "vertical_name", null: false
    t.index ["vertical_name"], name: "index_vertical_percents_on_vertical_name", unique: true
  end

  add_foreign_key "achievement_entry_details", "action_plan_rows"
  add_foreign_key "achievement_submission_rows", "achievement_submissions"
  add_foreign_key "achievement_submission_rows", "action_plan_rows"
  add_foreign_key "achievement_submissions", "employees"
  add_foreign_key "achievement_submissions", "employees", column: "coo_approver_id"
  add_foreign_key "achievement_submissions", "employees", column: "director_approver_id"
  add_foreign_key "achievement_submissions", "employees", column: "po_approver_id"
  add_foreign_key "achievement_submissions", "employees", column: "vertical_approver_id"
  add_foreign_key "action_plan_fco_mappings", "employees"
  add_foreign_key "action_plan_import_files", "users", column: "uploaded_by_id"
  add_foreign_key "action_plan_submissions", "employees"
  add_foreign_key "action_plan_submissions", "employees", column: "coo_approver_id"
  add_foreign_key "action_plan_submissions", "employees", column: "director_approver_id"
  add_foreign_key "action_plan_submissions", "employees", column: "po_approver_id"
  add_foreign_key "action_plan_submissions", "project_ownerships"
  add_foreign_key "action_plan_vertical_mappings", "employees"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bli_activities", "employees"
  add_foreign_key "budget_utilizations", "users", column: "submitted_by_id"
  add_foreign_key "budget_utilizations", "users", column: "updated_by_id"
  add_foreign_key "donor_report_uploads", "donor_report_types"
  add_foreign_key "donor_report_uploads", "users", column: "uploaded_by_id"
  add_foreign_key "employee_vertical_mappings", "employees"
  add_foreign_key "employee_vertical_mappings", "vertical_percents"
  add_foreign_key "fund_report_uploads", "fund_report_types"
  add_foreign_key "fund_report_uploads", "users", column: "uploaded_by_id"
  add_foreign_key "parent_activity_assignments", "employees"
  add_foreign_key "parent_activity_assignments", "vertical_percents"
  add_foreign_key "pb_import_files", "users", column: "approved_by_id"
  add_foreign_key "pb_import_files", "users", column: "uploaded_by_id"
  add_foreign_key "pis_report_documents", "pis_document_types"
  add_foreign_key "pis_report_documents", "users", column: "uploaded_by_id"
  add_foreign_key "plan_submission_items", "bli_activities"
  add_foreign_key "plan_submission_items", "plan_submissions"
  add_foreign_key "plan_submissions", "employees"
  add_foreign_key "project_information_sheets", "users", column: "uploaded_by_id"
  add_foreign_key "project_summary_submission_items", "project_summary_submissions"
  add_foreign_key "project_summary_submissions", "employees"
  add_foreign_key "project_summary_submissions", "employees", column: "approver_id"
  add_foreign_key "project_summary_submissions", "employees", column: "first_approver_id"
  add_foreign_key "users", "employees"
end

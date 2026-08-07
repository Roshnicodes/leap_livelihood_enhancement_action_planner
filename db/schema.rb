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

ActiveRecord::Schema[8.1].define(version: 2026_08_07_040100) do
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
    t.index ["employee_id"], name: "index_action_plan_fco_mappings_on_employee_id"
    t.index ["fco_id"], name: "index_action_plan_fco_mappings_on_fco_id"
  end

  create_table "action_plan_import_files", force: :cascade do |t|
    t.integer "byte_size", default: 0, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "import_type", null: false
    t.datetime "imported_at", null: false
    t.string "original_filename", null: false
    t.integer "row_count"
    t.string "status", default: "saved", null: false
    t.string "storage_path", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
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
    t.index ["import_flag", "to_id", "project_name"], name: "idx_action_plan_rows_active_to_project"
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
    t.index ["employee_id", "project_name", "vertical_name"], name: "index_bli_activities_on_employee_project_vertical"
    t.index ["employee_id", "vertical_name", "project_name", "activity_name"], name: "index_bli_activities_on_employee_vertical_project_activity"
    t.index ["employee_id"], name: "index_bli_activities_on_employee_id"
    t.index ["financial_year"], name: "index_bli_activities_on_financial_year"
    t.index ["project_name"], name: "index_bli_activities_on_project_name"
    t.index ["vertical_name", "project_name"], name: "index_bli_activities_on_vertical_project"
    t.index ["vertical_name"], name: "index_bli_activities_on_vertical_name"
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
    t.index ["department"], name: "index_employees_on_department"
    t.index ["email"], name: "index_employees_on_email"
    t.index ["employee_code"], name: "index_employees_on_employee_code", unique: true
    t.index ["name"], name: "index_employees_on_name"
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
    t.index ["mode"], name: "index_plan_submissions_on_mode"
    t.index ["submitted_at"], name: "index_plan_submissions_on_submitted_at"
  end

  create_table "project_ownerships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_id"
    t.string "po_id", null: false
    t.string "po_name"
    t.string "project_name", null: false
    t.string "project_owner_id"
    t.datetime "updated_at", null: false
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
    t.index ["first_approver_id"], name: "index_project_summary_submissions_on_first_approver_id"
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
  add_foreign_key "employee_vertical_mappings", "employees"
  add_foreign_key "employee_vertical_mappings", "vertical_percents"
  add_foreign_key "parent_activity_assignments", "employees"
  add_foreign_key "parent_activity_assignments", "vertical_percents"
  add_foreign_key "plan_submission_items", "bli_activities"
  add_foreign_key "plan_submission_items", "plan_submissions"
  add_foreign_key "plan_submissions", "employees"
  add_foreign_key "project_summary_submission_items", "project_summary_submissions"
  add_foreign_key "project_summary_submissions", "employees"
  add_foreign_key "project_summary_submissions", "employees", column: "approver_id"
  add_foreign_key "project_summary_submissions", "employees", column: "first_approver_id"
  add_foreign_key "users", "employees"
end

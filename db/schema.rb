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

ActiveRecord::Schema[8.1].define(version: 2026_07_29_103000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["employee_id"], name: "index_bli_activities_on_employee_id"
    t.index ["financial_year"], name: "index_bli_activities_on_financial_year"
    t.index ["project_name"], name: "index_bli_activities_on_project_name"
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

  create_table "plan_submission_items", force: :cascade do |t|
    t.bigint "bli_activity_id", null: false
    t.decimal "changed_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "original_fund", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "plan_submission_id", null: false
    t.text "remark"
    t.datetime "updated_at", null: false
    t.index ["bli_activity_id"], name: "index_plan_submission_items_on_bli_activity_id"
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
    t.index ["employee_id"], name: "index_plan_submissions_on_employee_id"
    t.index ["mode"], name: "index_plan_submissions_on_mode"
    t.index ["submitted_at"], name: "index_plan_submissions_on_submitted_at"
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
    t.index ["project_name"], name: "index_project_summary_submission_items_on_project_name"
    t.index ["project_summary_submission_id"], name: "idx_on_project_summary_submission_id_82944b0850"
  end

  create_table "project_summary_submissions", force: :cascade do |t|
    t.text "approval_remark"
    t.bigint "approver_id"
    t.datetime "created_at", null: false
    t.bigint "employee_id", null: false
    t.datetime "reviewed_at"
    t.string "status", default: "pending", null: false
    t.text "submission_remark"
    t.datetime "submitted_at", null: false
    t.decimal "total_amount", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["approver_id"], name: "index_project_summary_submissions_on_approver_id"
    t.index ["employee_id"], name: "index_project_summary_submissions_on_employee_id"
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

  add_foreign_key "bli_activities", "employees"
  add_foreign_key "employee_vertical_mappings", "employees"
  add_foreign_key "employee_vertical_mappings", "vertical_percents"
  add_foreign_key "plan_submission_items", "bli_activities"
  add_foreign_key "plan_submission_items", "plan_submissions"
  add_foreign_key "plan_submissions", "employees"
  add_foreign_key "project_summary_submission_items", "project_summary_submissions"
  add_foreign_key "project_summary_submissions", "employees"
  add_foreign_key "project_summary_submissions", "employees", column: "approver_id"
  add_foreign_key "users", "employees"
end

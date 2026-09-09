require "test_helper"
require "csv"

class ProjectSummaryRecordsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "summary-record-admin", role: "admin", password: "secret")
    @employee_one = Employee.create!(employee_code: "PSR-1", name: "Summary One", active: true)
    @employee_two = Employee.create!(employee_code: "PSR-2", name: "Summary Two", active: true)
    VerticalPercent.create!(vertical_name: "Livelihood", total: 100, apr: 100)

    @current_activity = BliActivity.create!(
      employee: @employee_one,
      project_name: "Shared Summary Project",
      vertical_name: "Livelihood",
      activity_name: "Seed support",
      responsible_user_name: @employee_one.name,
      bli_code: "1.1",
      name: "Seed BLI",
      allocated_fund: 60,
      remaining_fund: 60
    )
    BliActivity.create!(
      employee: @employee_one,
      project_name: "Shared Summary Project",
      vertical_name: "Livelihood",
      activity_name: "Seed support",
      responsible_user_name: @employee_one.name,
      bli_code: "1.1.1",
      name: "Seed BLI extra",
      allocated_fund: 40,
      remaining_fund: 40
    )
    BliActivity.create!(
      employee: @employee_two,
      project_name: "Shared Summary Project",
      vertical_name: "Livelihood",
      activity_name: "Training support",
      responsible_user_name: @employee_two.name,
      bli_code: "1.2",
      name: "Training BLI",
      allocated_fund: 50,
      remaining_fund: 50
    )
    inactive_employee = Employee.create!(employee_code: "PSR-3", name: "Inactive Summary", active: false)
    BliActivity.create!(
      employee: inactive_employee,
      project_name: "Shared Summary Project",
      vertical_name: "Livelihood",
      activity_name: "Inactive employee support",
      responsible_user_name: inactive_employee.name,
      bli_code: "1.3",
      name: "Inactive BLI",
      allocated_fund: 25,
      remaining_fund: 25
    )
    stale_submission = ProjectSummarySubmission.create!(
      employee: @employee_one,
      total_amount: 90,
      status: "approved",
      submitted_at: 2.days.ago
    )
    stale_submission.project_summary_submission_items.create!(
      project_name: @current_activity.project_name,
      activity_name: @current_activity.activity_name,
      vertical_name: @current_activity.vertical_name,
      total_amount: 90,
      changed_total: 90,
      apr: 90
    )

    post login_path, params: { login: @admin.login, password: "secret" }
  end

  test "project summary record counts unique projects and exports current allocated budget" do
    get project_summary_records_path

    assert_response :success
    assert_select ".header-card span", text: "Total Projects"
    assert_select ".header-card strong", text: "1"
    assert_select ".project-summary-record-metrics .metric", text: /Verticals\s*1/
    assert_select ".project-summary-record-metrics .metric", text: /No of Activity\s*4/
    assert_select "[data-global-record-count]", text: /3 summary rows/

    get plan_submissions_path(format: :csv)
    allocated_rows = CSV.parse(response.body, headers: true)
    allocated_total = allocated_rows.sum { |row| BigDecimal(row["Allocated Budget"]) }

    get project_summary_records_path(format: :csv)
    summary_rows = CSV.parse(response.body, headers: true)
    summary_total = summary_rows.sum { |row| BigDecimal(row["Total Amount"]) }
    summary_activity_count = summary_rows.sum { |row| row["P&B Activity Count"].to_i }
    seed_row = summary_rows.find { |row| row["ASA Activity"] == "Seed support" }

    assert_equal BigDecimal("175"), allocated_total
    assert_equal allocated_total, summary_total
    assert_equal allocated_rows.size, summary_activity_count
    assert_equal "100.0", BigDecimal(seed_row["Total Amount"]).to_s("F")
    assert_equal "100.0", BigDecimal(seed_row["Changed Total"]).to_s("F")
    assert_equal "2", seed_row["P&B Activity Count"]
  end
end

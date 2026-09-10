require "test_helper"
require "csv"

class ProjectSummaryRecordsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "summary-record-admin", role: "admin", password: "secret")
    @employee_one = Employee.create!(employee_code: "PSR-1", name: "Summary One", active: true)
    @employee_two = Employee.create!(employee_code: "PSR-2", name: "Summary Two", active: true)
    VerticalPercent.create!(vertical_name: "Livelihood", total: 100, apr: 100)
    ProjectInformationSheet.create!(project_id: "PID-SHARED", project_title: "Shared Summary Project")
    ActionPlanRow.create!(
      po_id: "PO-SHARED",
      project_id: "AP-SHARED",
      project_name: "Shared Summary Project",
      asa_theme_id: "10",
      asa_theme: "Livelihood Theme",
      asa_activity_id: "10.1",
      asa_activity_name: "Seed support",
      activity: "Seed support"
    )

    @current_activity = BliActivity.create!(
      employee: @employee_one,
      project_name: "Shared Summary Project",
      office_name: "Office A",
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
      office_name: "Office A",
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
      office_name: "Office B",
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
      office_name: "Office C",
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
    assert_select "[data-global-record-count]", text: /4 summary rows/
    assert_select "tr[data-summary-row]", 4

    get plan_submissions_path(format: :csv)
    allocated_rows = CSV.parse(response.body, headers: true)
    allocated_total = allocated_rows.sum { |row| BigDecimal(row["Allocated Budget"]) }

    get project_summary_records_path(format: :csv)
    summary_rows = CSV.parse(response.body, headers: true)
    summary_total = summary_rows.sum { |row| BigDecimal(row["Total Amount"]) }
    summary_activity_count = summary_rows.sum { |row| row["P&B Activity Count"].to_i }
    seed_rows = summary_rows.select { |row| row["ASA Activity"] == "Seed support" }
    seed_bli_row = summary_rows.find { |row| row["Project Bli Code"] == "1.1" }
    expected_source_headers = [
      "Project ID",
      "Project Name",
      "Office Name",
      "Project Bli Code",
      "Project_Bli_Name",
      "Bli Allocated Fund",
      "ASA Theme ID",
      "ASA Theme",
      "ASA Activity ID",
      "ASA Activity",
      "Responsible Users"
    ]

    assert_equal BigDecimal("175"), allocated_total
    assert_equal allocated_total, summary_total
    assert_equal allocated_rows.size, summary_rows.size
    assert_equal allocated_rows.size, summary_activity_count
    assert_equal expected_source_headers, summary_rows.headers.first(expected_source_headers.size)
    assert_equal "100.0", seed_rows.sum { |row| BigDecimal(row["Total Amount"]) }.to_s("F")
    assert_equal "100.0", seed_rows.sum { |row| BigDecimal(row["Changed Total"]) }.to_s("F")
    assert_equal "1", seed_bli_row["P&B Activity Count"]
    assert_equal "PID-SHARED", seed_bli_row["Project ID"]
    assert_equal "Shared Summary Project", seed_bli_row["Project Name"]
    assert_equal "Office A", seed_bli_row["Office Name"]
    assert_equal "Seed BLI", seed_bli_row["Project_Bli_Name"]
    assert_equal "60.0", BigDecimal(seed_bli_row["Bli Allocated Fund"]).to_s("F")
    assert_equal "10", seed_bli_row["ASA Theme ID"]
    assert_equal "Livelihood Theme", seed_bli_row["ASA Theme"]
    assert_equal "10.1", seed_bli_row["ASA Activity ID"]
    assert_equal @employee_one.name, seed_bli_row["Responsible Users"]
    assert_equal "1.1", seed_bli_row["Project BLI Code"]
  end
end

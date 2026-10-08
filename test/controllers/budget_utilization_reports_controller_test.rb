require "test_helper"

class BudgetUtilizationReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-budget-report", role: "admin", password: "secret")
    @field_employee = Employee.create!(employee_code: "2002", name: "Field User")
    @vertical_viewer = Employee.create!(employee_code: "2003", name: "Agriculture Viewer", active: true)
    @vertical_viewer_user = User.create!(login: @vertical_viewer.employee_code, employee: @vertical_viewer, password: "secret")
    @agriculture = VerticalPercent.create!(vertical_name: "Agriculture")
    EmployeeVerticalMapping.create!(employee: @vertical_viewer, vertical_percent: @agriculture)

    create_activity(project_name: "Project A", bli_code: "1.1", activity_name: "Seeds", allocated_fund: 1_000)
    create_activity(project_name: "Project A", bli_code: "1.1", activity_name: "Seed support", allocated_fund: 500)
    create_activity(project_name: "Project A", bli_code: "", activity_name: "Blank code support", allocated_fund: 125)
    create_activity(project_name: "Project A", bli_code: "1.1, 1.2", activity_name: "Combined code support", allocated_fund: 75)

    BudgetUtilization.create!(
      project_name: "Project A",
      activity_name: "Seeds",
      vertical_name: "Agriculture",
      bli_code: "1.1",
      month: "apr",
      planned_amount: 150,
      utilized_amount: 75,
      status: "submitted",
      updated_by: @admin,
      submitted_by: @admin,
      submitted_at: Time.current
    )

    post login_path, params: { login: @admin.login, password: "secret" }
  end

  test "xlsx report sums allocated fund for duplicate and non single bli rows" do
    get budget_utilization_reports_path(format: :xlsx)

    assert_response :success
    rows = xlsx_rows(response.body)
    project_row = rows.find { |row| row["Project"] == "Project A" }

    assert project_row
    assert_equal BigDecimal("1700"), BigDecimal(project_row.fetch("Total Allocated Budget"))
  end

  test "non MIS users only receive report data for their assigned verticals" do
    health = VerticalPercent.create!(vertical_name: "Health")
    create_activity(project_name: "Project B", bli_code: "2.1", activity_name: "Health Camp", allocated_fund: 500, vertical_name: health.vertical_name)
    BudgetUtilization.create!(
      project_name: "Project B",
      activity_name: "Health Camp",
      vertical_name: health.vertical_name,
      bli_code: "2.1",
      month: "apr",
      planned_amount: 50,
      utilized_amount: 20,
      status: "submitted",
      updated_by: @admin,
      submitted_by: @admin,
      submitted_at: Time.current
    )

    delete logout_path
    post login_path, params: { login: @vertical_viewer_user.login, password: "secret" }

    get budget_utilization_reports_path

    assert_response :success
    assert_includes response.body, "Project A"
    refute_includes response.body, "Project B"

    get budget_utilization_reports_path(format: :xlsx)

    assert_response :success
    rows = xlsx_rows(response.body)
    assert_includes rows.map { |row| row["Project"] }, "Project A"
    assert_not_includes rows.map { |row| row["Project"] }, "Project B"
  end

  private

  def create_activity(attributes)
    BliActivity.create!(
      {
        employee: @field_employee,
        vertical_name: "Agriculture",
        responsible_user_name: @field_employee.name
      }.merge(attributes)
    )
  end

  def xlsx_rows(body)
    tempfile = Tempfile.new([ "budget-utilization-report", ".xlsx" ])
    tempfile.binmode
    tempfile.write(body)
    tempfile.close

    SpreadsheetRows.read(tempfile.path, sheet: :first, header_match: [ "Project", "Total Allocated Budget" ])
  ensure
    tempfile&.unlink
  end
end

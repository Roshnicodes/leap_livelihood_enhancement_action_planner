require "test_helper"

class BudgetUtilizationReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-budget-report", role: "admin", password: "secret")
    @field_employee = Employee.create!(employee_code: "2002", name: "Field User")

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

require "test_helper"
require "zip"

class MisBudgetUtilizationReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-detail-budget", role: "admin", password: "secret")
    @employee = Employee.create!(employee_code: "2003", name: "Field User", office_name: "Employee Office", active: true)
    @user = User.create!(login: "field-budget", employee: @employee, password: "secret")

    VerticalPercent.create!(vertical_name: "Agriculture", apr: 10, may: 10, total: 20)
    BliActivity.create!(
      employee: @employee,
      name: "Seeds BLI",
      bli_code: "1.1",
      allocated_fund: 1_000,
      financial_year: "2026-2027",
      project_name: "Project A",
      office_name: nil,
      vertical_name: "Agriculture",
      activity_name: "Seeds",
      responsible_user_name: @employee.name
    )

    BudgetUtilization.create!(
      project_name: "Project A",
      activity_name: "Seeds",
      vertical_name: "Agriculture",
      bli_code: "1.1",
      month: "apr",
      planned_amount: 100,
      utilized_amount: 75,
      status: "submitted",
      updated_by: @admin,
      submitted_by: @admin,
      submitted_at: Time.current
    )
  end

  test "admin can view MIS budget utilization report with BLI and monthly allocated columns" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get mis_budget_utilization_reports_path

    assert_response :success
    assert_select "h1", "MIS Budget Utilization Report"
    assert_select "thead th:nth-child(1)", "S.No."
    assert_select "thead th:nth-child(2)", "Project Name"
    assert_select "th", "Project BLI Name"
    assert_select "th", "BLI Code"
    assert_select "th", "BLI Allocated Fund"
    assert_select "th", "Financial Year"
    assert_select "th", "Office Name"
    assert_select "th", "Vertical"
    assert_select "th", "Activity"
    assert_select "th", "Responsible Users"
    assert_select "th", "Apr Month Allocated Budget"
    assert_select "th", text: "Apr Monthly Allocated Budget", count: 0
    assert_select "th", "Apr"
    assert_select "tbody tr:first-child td:first-child .code-pill", "1"
    assert_select "tbody tr:first-child td:nth-child(2) strong", "Project A"
    assert_select "tbody tr:first-child td:nth-child(3) strong", false
    assert_select ".sidebar-section.is-open .sidebar-section-toggle span", "P&B"
    assert_select ".sidebar-section.is-open a[href=\"#{mis_budget_utilization_reports_path}\"]", /MIS Budget Utilization/
    assert_includes response.body, "Seeds BLI"
    assert_includes response.body, "Employee Office"
  end

  test "MIS xlsx export is password protected and includes requested columns" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get mis_budget_utilization_reports_path(format: :xlsx)

    assert_response :success
    assert_equal XlsxWorkbook::CONTENT_TYPE, response.media_type

    sheet_xml = xlsx_sheet_xml(response.body)
    assert_match(/<sheetProtection[^>]*password="[0-9A-F]+"/, sheet_xml)

    rows = xlsx_rows(response.body)
    row = rows.find { |candidate| candidate["Project Name"] == "Project A" }

    assert row
    assert_equal 1, BigDecimal(row.fetch("S.No.")).to_i
    assert_equal "Seeds BLI", row["Project BLI Name"]
    assert_equal "Employee Office", row["Office Name"]
    assert_equal "1.1", row["BLI Code"]
    assert_equal BigDecimal("1000"), BigDecimal(row.fetch("BLI Allocated Fund"))
    assert_equal BigDecimal("100"), BigDecimal(row.fetch("Apr Month Allocated Budget"))
    assert_equal BigDecimal("75"), BigDecimal(row.fetch("Apr"))
  end

  test "non admin cannot open MIS budget utilization report" do
    post login_path, params: { login: @user.login, password: "secret" }

    get mis_budget_utilization_reports_path

    assert_redirected_to dashboard_path
  end

  private

  def xlsx_sheet_xml(body)
    Zip::File.open_buffer(StringIO.new(body)) do |zip|
      return zip.read("xl/worksheets/sheet1.xml")
    end
  end

  def xlsx_rows(body)
    tempfile = Tempfile.new([ "mis-budget-utilization-report", ".xlsx" ])
    tempfile.binmode
    tempfile.write(body)
    tempfile.close

    SpreadsheetRows.read(tempfile.path, sheet: :first, header_match: [ "S.No.", "Project Name", "Apr Month Allocated Budget" ])
  ensure
    tempfile&.unlink
  end
end

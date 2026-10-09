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
    BudgetUtilization.create!(
      project_name: "Project A",
      activity_name: "Seeds",
      vertical_name: "Agriculture",
      bli_code: "1.1",
      month: "jun",
      planned_amount: 100,
      utilized_amount: 25,
      status: "submitted",
      updated_by: @admin,
      submitted_by: @admin,
      submitted_at: Time.current
    )

    @other_employee = Employee.create!(employee_code: "2004", name: "Other User", office_name: "Other Office", active: true)
    VerticalPercent.create!(vertical_name: "Health", apr: 20, total: 20)
    BliActivity.create!(
      employee: @other_employee,
      name: "Health BLI",
      bli_code: "2.1",
      allocated_fund: 2_000,
      financial_year: "2026-2027",
      project_name: "Project B",
      office_name: nil,
      vertical_name: "Health",
      activity_name: "Health Camp",
      responsible_user_name: @other_employee.name
    )
    BudgetUtilization.create!(
      project_name: "Project B",
      activity_name: "Health Camp",
      vertical_name: "Health",
      bli_code: "2.1",
      month: "apr",
      planned_amount: 200,
      utilized_amount: 45,
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
    assert_select "th", "Apr Expenses"
    assert_select "th", text: "Apr", count: 0
    assert_select "th", text: "Q1", count: 0
    assert_select "tbody tr:first-child td:first-child .code-pill", "1"
    assert_select "tbody tr:first-child td:nth-child(2) strong", "Project A"
    assert_select "tbody tr:first-child td:nth-child(3) strong", false
    assert_select ".sidebar-section.is-open .sidebar-section-toggle span", "P&B"
    assert_select ".sidebar-section.is-open a[href=\"#{mis_budget_utilization_reports_path}\"]", /MIS Budget Utilization/
    assert_includes response.body, "Seeds BLI"
    assert_includes response.body, "Employee Office"
    refute_includes response.body, "Submitted Details"
    assert_no_match(/Submitted \d{1,2} [A-Z][a-z]{2} \d{4}/, response.body)
  end

  test "admin can filter MIS budget utilization report" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get mis_budget_utilization_reports_path(
      project: "Project A",
      period: "monthly",
      period_month: "apr",
      vertical: "Agriculture",
      office: "Employee Office",
      user: "Field User"
    )

    assert_response :success
    assert_select ".mis-budget-filter-toolbar .filter-label", "Choose Project"
    assert_select ".mis-budget-filter-toolbar .filter-label", "Period"
    assert_select ".mis-budget-filter-toolbar .filter-label", "Month"
    assert_select ".mis-budget-filter-toolbar .filter-label", "Vertical"
    assert_select ".mis-budget-filter-toolbar .filter-label", "Office"
    assert_select ".mis-budget-filter-toolbar .filter-label", "User"
    assert_select "tbody td:nth-child(2) strong", "Project A"
    assert_select "tbody td:nth-child(2) strong", text: "Project B", count: 0
    assert_select "th", "Apr Expenses"
    assert_select "th", text: "May Expenses", count: 0
  end

  test "MIS summary cards use the selected quarter or month allocation" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get mis_budget_utilization_reports_path(period: "quarter_1")

    assert_response :success
    assert_select ".mis-budget-metrics .metric:nth-child(3) strong", "₹600"
    assert_select ".mis-budget-metrics .metric:nth-child(4) strong", "₹145"
    assert_select ".mis-budget-metrics .metric:nth-child(5) strong", "₹455"
    assert_select "tbody tr:first-child td:nth-child(12)", "₹100"

    get mis_budget_utilization_reports_path(period: "monthly", period_month: "apr")

    assert_response :success
    assert_select ".mis-budget-metrics .metric:nth-child(3) strong", "₹500"
    assert_select ".mis-budget-metrics .metric:nth-child(4) strong", "₹120"
    assert_select ".mis-budget-metrics .metric:nth-child(5) strong", "₹380"
    assert_select "tbody tr:first-child td:nth-child(12)", "₹25"
  end

  test "MIS office filter uses cleaned office names without changing office display" do
    branch_employee = Employee.create!(
      employee_code: "2005",
      name: "Branch Office User",
      branch: "FCO-Betul",
      sub_branch: "TO-Betul",
      active: true
    )
    BliActivity.create!(
      employee: branch_employee,
      name: "Branch Office BLI",
      bli_code: "3.1",
      allocated_fund: 500,
      financial_year: "2026-2027",
      project_name: "Project C",
      office_name: nil,
      vertical_name: "Agriculture",
      activity_name: "Branch Office Activity",
      responsible_user_name: branch_employee.name
    )
    BudgetUtilization.create!(
      project_name: "Project C",
      activity_name: "Branch Office Activity",
      vertical_name: "Agriculture",
      bli_code: "3.1",
      month: "apr",
      planned_amount: 50,
      utilized_amount: 20,
      status: "submitted",
      updated_by: @admin,
      submitted_by: @admin,
      submitted_at: Time.current
    )

    direct_employee = Employee.create!(employee_code: "2006", name: "Direct Office User", active: true)
    BliActivity.create!(
      employee: direct_employee,
      name: "Direct Office BLI",
      bli_code: "4.1",
      allocated_fund: 500,
      financial_year: "2026-2027",
      project_name: "Project D",
      office_name: "HO- Bhopal / HO-Bhopal",
      vertical_name: "Agriculture",
      activity_name: "Direct Office Activity",
      responsible_user_name: direct_employee.name
    )
    BudgetUtilization.create!(
      project_name: "Project D",
      activity_name: "Direct Office Activity",
      vertical_name: "Agriculture",
      bli_code: "4.1",
      month: "apr",
      planned_amount: 50,
      utilized_amount: 20,
      status: "submitted",
      updated_by: @admin,
      submitted_by: @admin,
      submitted_at: Time.current
    )

    post login_path, params: { login: @admin.login, password: "secret" }
    get mis_budget_utilization_reports_path

    assert_response :success
    assert_includes response.body, "FCO-Betul / TO-Betul"
    assert_includes response.body, "HO- Bhopal / HO-Bhopal"
    assert_select ".mis-budget-filter-toolbar select[name='office'] option", text: "HO-Bhopal", count: 1
    assert_select ".mis-budget-filter-toolbar select[name='office'] option", text: "HO- Bhopal / HO-Bhopal", count: 0
    assert_select ".mis-budget-filter-toolbar select[name='office'] option", text: "FCO-Betul / TO-Betul", count: 1

    get mis_budget_utilization_reports_path(office: "FCO-Betul / TO-Betul")

    assert_response :success
    assert_select "tbody td:nth-child(2) strong", "Project C"
    assert_select "tbody td:nth-child(2) strong", text: "Project D", count: 0

    get mis_budget_utilization_reports_path(office: "HO-Bhopal")

    assert_response :success
    assert_select "tbody td:nth-child(2) strong", "Project D"
    assert_select "tbody td:nth-child(2) strong", text: "Project C", count: 0
  end

  test "MIS xlsx export opens without sheet protection and includes requested columns" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get mis_budget_utilization_reports_path(format: :xlsx)

    assert_response :success
    assert_equal XlsxWorkbook::CONTENT_TYPE, response.media_type

    sheet_xml = xlsx_sheet_xml(response.body)
    refute_match(/<sheetProtection\b/, sheet_xml)

    rows = xlsx_rows(response.body)
    row = rows.find { |candidate| candidate["Project Name"] == "Project A" }

    assert row
    assert_equal 1, BigDecimal(row.fetch("S.No.")).to_i
    assert_equal "Seeds BLI", row["Project BLI Name"]
    assert_equal "Employee Office", row["Office Name"]
    assert_equal "1.1", row["BLI Code"]
    assert_equal BigDecimal("1000"), BigDecimal(row.fetch("BLI Allocated Fund"))
    assert_equal BigDecimal("100"), BigDecimal(row.fetch("Apr Month Allocated Budget"))
    assert_equal BigDecimal("75"), BigDecimal(row.fetch("Apr Expenses"))
    assert_nil row["Apr Submitted Details"]
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

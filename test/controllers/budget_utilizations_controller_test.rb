require "test_helper"
require "csv"
require "zip"

class BudgetUtilizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @finance_employee = Employee.create!(employee_code: BudgetUtilization::FINANCE_EMPLOYEE_CODE, name: "Accounts User")
    @finance_user = User.create!(login: @finance_employee.employee_code, employee: @finance_employee, password: "secret")
    @field_employee = Employee.create!(employee_code: "2001", name: "Field User")

    VerticalPercent.create!(vertical_name: "Agriculture", apr: 10, may: 10, total: 20)
    create_activity(project_name: "Project A", bli_code: "1.1", activity_name: "Seeds")
    create_activity(project_name: "Project B", bli_code: "2.1", activity_name: "Training")
    ActionPlanRow.create!(po_id: "PO-A", project_id: "PID-A", project_name: "Project A")
    ActionPlanRow.create!(po_id: "PO-B", project_id: "PID-B", project_name: "Project B")

    BudgetUtilization.create!(
      project_name: "Project A",
      activity_name: "Seeds",
      vertical_name: "Agriculture",
      bli_code: "1.1",
      month: "apr",
      planned_amount: 100,
      utilized_amount: 75,
      status: "draft",
      updated_by: @finance_user
    )

    post login_path, params: { login: @finance_user.login, password: "secret" }
  end

  test "index includes all projects option and renders all project rows in view mode" do
    get budget_utilizations_path(project: "all", month: "apr")

    assert_response :success
    assert_select "option[value='all']", text: "All Projects"
    assert_select "h2", "All Projects"
    assert_includes response.body, "Project A"
    assert_includes response.body, "Project B"
    assert_includes response.body, "PID-A"
    assert_includes response.body, "1.1 Seeds"
    assert_select "input[data-budget-utilization-input]", 0
    assert_select "a[href='#{budget_utilizations_path(project: "all", month: "apr", format: :xlsx)}']", text: "Download Excel Sheet"
    assert_select ".budget-excel-panel"
    assert_select "form[action='#{import_budget_utilizations_path}'][method='post']"
    assert_select "input[type='file'][name='budget_file']"
  end

  test "project ids fall back to close project aliases and project titles" do
    ActionPlanRow.create!(po_id: "PO-AR", project_id: "52", project_name: "Aranya-PGPL")
    ProjectInformationSheet.create!(project_id: "13", project_title: "Construction of Dugwells.")
    create_activity(project_name: "Aranya-ASA", bli_code: "3.1", activity_name: "Aranya Activity")
    create_activity(
      project_name: "Where there is well",
      bli_code: "4.1",
      activity_name: "Dugwell",
      name: "Constructuion of dug wells"
    )

    get budget_utilizations_path(project: "all", month: "apr")

    assert_response :success
    assert_includes response.body, "52"
    assert_includes response.body, "13"
  end

  test "all projects xlsx download includes selected month rows across projects" do
    get budget_utilizations_path(project: "all", month: "may", format: :xlsx)

    assert_response :success
    assert_equal XlsxWorkbook::CONTENT_TYPE, response.media_type
    assert_includes response.headers["Content-Disposition"], "budget_utilization_all_projects_may_"

    sheet_xml = xlsx_sheet_xml(response.body)
    assert_includes sheet_xml, "Project A"
    assert_includes sheet_xml, "Project B"
    assert_includes sheet_xml, "Project ID"
    assert_includes sheet_xml, "PID-A"
    assert_includes sheet_xml, "Project BLI Code Project BLI"
    assert_includes sheet_xml, "1.1 Seeds"
    assert_includes sheet_xml, "May Planned Budget"
    assert_includes sheet_xml, "May Utilized"
    assert_includes sheet_xml, "<sheetProtection"
    assert_no_match(/<c r="K5"[^>]*s="4"/, sheet_xml)
    assert_match(/<c r="M5"[^>]*s="4"/, sheet_xml)
  end

  test "imports updated excel values only for selected month" do
    upload = budget_upload_file(month: "May", rows: [
      [ 1, "PID-A", "Project A", "Agriculture", "1.1", "Seeds", "1.1 Seeds", 1_000, 999, 1, 999, 100, 123, nil ],
      [ 2, "PID-B", "Project B", "Agriculture", "2.1", "Training", "2.1 Training", 1_000, 0, 1_000, 888, 100, 456, nil ]
    ])

    post import_budget_utilizations_path, params: {
      project: "all",
      month: "may",
      budget_file: upload
    }

    assert_redirected_to budget_utilizations_path(project: "all", month: "may")
    assert_equal 75, BudgetUtilization.find_by!(project_name: "Project A", bli_code: "1.1", month: "apr").utilized_amount

    project_a_may = BudgetUtilization.find_by!(project_name: "Project A", bli_code: "1.1", month: "may")
    project_b_may = BudgetUtilization.find_by!(project_name: "Project B", bli_code: "2.1", month: "may")

    assert_equal BigDecimal("123"), project_a_may.utilized_amount
    assert_equal BigDecimal("456"), project_b_may.utilized_amount
    assert_equal "draft", project_a_may.status
    assert_nil project_a_may.submitted_at
    assert_nil project_a_may.submitted_by
  ensure
    upload&.tempfile&.close
    upload&.tempfile&.unlink
  end

  private

  def create_activity(attributes)
    BliActivity.create!(
      {
        employee: @field_employee,
        vertical_name: "Agriculture",
        responsible_user_name: @field_employee.name,
        allocated_fund: 1_000
      }.merge(attributes)
    )
  end

  def xlsx_sheet_xml(body)
    Zip::File.open_buffer(StringIO.new(body)) do |zip|
      return zip.read("xl/worksheets/sheet1.xml")
    end
  end

  def budget_upload_file(month:, rows:)
    csv = CSV.generate do |data|
      data << [
        "S.No.",
        "Project ID",
        "Project",
        "Project P&B",
        "Project BLI Code",
        "Project BLI",
        "Project BLI Code Project BLI",
        "Total Allocated Budget",
        "Total Expenditure",
        "Total Remaining Budget",
        "Apr Utilized",
        "#{month} Planned Budget",
        "#{month} Utilized",
        "#{month} Details"
      ]
      rows.each { |row| data << row }
    end
    tempfile = Tempfile.new([ "budget-utilization", ".xlsx" ])
    tempfile.binmode
    tempfile.write(
      XlsxWorkbook.from_csv(
        csv,
        title: "Budget Utilization",
        sheet_name: "Utilization",
        protected: true,
        unlocked_headers: [ "#{month} Utilized" ]
      )
    )
    tempfile.rewind

    Rack::Test::UploadedFile.new(tempfile.path, XlsxWorkbook::CONTENT_TYPE, true).tap do |file|
      file.instance_variable_set(:@tempfile, tempfile)
    end
  end
end

require "test_helper"
require "tempfile"

class AdminManagementTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-test", role: "admin", password: "secret")
    post login_path, params: { login: @admin.login, password: "secret" }
  end

  test "employee admin page renders and toggles employee access" do
    employee = Employee.create!(employee_code: "1001", name: "Test Employee", active: true)

    get admin_employees_path
    assert_response :success
    assert_select "h1", "Employee Control"
    assert_includes response.body, "Test Employee"

    patch toggle_active_admin_employee_path(employee)

    assert_redirected_to admin_employees_path
    assert_not employee.reload.active?
  end

  test "employee activity counts ignore archived and disabled pb rows" do
    employee = Employee.create!(employee_code: "1001A", name: "Count Employee", active: true)
    BliActivity.create!(
      employee: employee,
      project_name: "Current Project",
      vertical_name: "Current Vertical",
      activity_name: "Current Activity",
      responsible_user_name: employee.name,
      allocated_fund: 100,
      active: true,
      import_flag: 0
    )
    BliActivity.create!(
      employee: employee,
      project_name: "Disabled Project",
      vertical_name: "Current Vertical",
      activity_name: "Disabled Activity",
      responsible_user_name: employee.name,
      allocated_fund: 100,
      active: false,
      import_flag: 0
    )
    BliActivity.create!(
      employee: employee,
      project_name: "Archived Project",
      vertical_name: "Old Vertical",
      activity_name: "Archived Activity",
      responsible_user_name: employee.name,
      allocated_fund: 100,
      active: true,
      import_flag: 1
    )

    get admin_employees_path

    assert_response :success
    assert_select "tbody tr", text: /Count Employee/ do
      assert_select "td:nth-child(9)", text: "1"
    end
  end

  test "employee pb menu ignores archived and disabled pb rows" do
    delete logout_path
    employee = Employee.create!(employee_code: "1001B", name: "Menu Employee", active: true)
    User.create!(login: employee.employee_code, employee: employee, password: "secret")
    BliActivity.create!(
      employee: employee,
      project_name: "Disabled Project",
      vertical_name: "Current Vertical",
      activity_name: "Disabled Activity",
      responsible_user_name: employee.name,
      allocated_fund: 100,
      active: false,
      import_flag: 0
    )
    BliActivity.create!(
      employee: employee,
      project_name: "Archived Project",
      vertical_name: "Old Vertical",
      activity_name: "Archived Activity",
      responsible_user_name: employee.name,
      allocated_fund: 100,
      active: true,
      import_flag: 1
    )

    post login_path, params: { login: employee.employee_code, password: "secret" }
    get report_information_path

    assert_response :success
    assert_select "a[href='#{plan_submissions_path}']", 0
    assert_select "a[href='#{project_summary_path}']", 0
    assert_select "a[href='#{project_summary_records_path}']", 0

    BliActivity.create!(
      employee: employee,
      project_name: "Current Project",
      vertical_name: "Current Vertical",
      activity_name: "Current Activity",
      responsible_user_name: employee.name,
      allocated_fund: 100,
      active: true,
      import_flag: 0
    )

    get report_information_path

    assert_response :success
    assert_select "a[href='#{plan_submissions_path}']"
    assert_select "a[href='#{project_summary_path}']"
    assert_select "a[href='#{project_summary_records_path}']"
  end

  test "fco admin page renders and disables mappings without deleting them" do
    employee = Employee.create!(employee_code: "1002", name: "FCO Employee")
    ActionPlanRow.create!(po_id: "PO-1", project_name: "Project A", user_id: "9", user_name: "Demo FCO")
    mapping = ActionPlanFcoMapping.create!(employee: employee, employee_code: employee.employee_code, fco_id: "9", fco_name: "Demo FCO")

    get admin_action_plan_fco_mapping_path(employee_id: employee.id)
    assert_response :success
    assert_select "h1", "FCO Access"
    assert_includes response.body, "Demo FCO"

    patch admin_toggle_action_plan_fco_mapping_path(mapping)

    assert_redirected_to admin_action_plan_fco_mapping_path(employee_id: employee.id)
    assert_not mapping.reload.active?
    assert ActionPlanFcoMapping.exists?(mapping.id)
    assert_not ActionPlanFcoMapping.ensure_for_employee(employee).exists?
  end

  test "action plan import page shows main file rows and disables without deleting" do
    row = ActionPlanRow.create!(
      po_id: "PO-2",
      project_name: "Project B",
      user_id: "14",
      user_name: "Main FCO",
      apr: 3,
      original_apr: 3
    )

    get admin_action_plan_imports_path
    assert_response :success
    assert_select "h2", "Main File Data"
    assert_select "td", text: /Project B/

    patch admin_toggle_action_plan_row_path(row)

    assert_redirected_to admin_action_plan_imports_path(anchor: "action-plan-main-file")
    assert_not row.reload.active?
    assert ActionPlanRow.current_import.exists?(row.id)
    assert_not ActionPlanRow.active_import.exists?(row.id)
    assert ActionPlanRow.disabled_import.exists?(row.id)
  end

  test "pb import page shows uploaded data and disables activity without deleting" do
    employee = Employee.create!(employee_code: "1003", name: "P&B Employee")
    activity = BliActivity.create!(
      employee: employee,
      project_name: "P&B Project",
      vertical_name: "Livelihood",
      activity_name: "Seed support",
      responsible_user_name: employee.name,
      allocated_fund: 100
    )

    get admin_pb_imports_path
    assert_response :success
    assert_select "h2", "P&B File Data"
    assert_includes response.body, "P&amp;B Project"

    patch admin_toggle_pb_bli_activity_path(activity)

    assert_redirected_to admin_pb_imports_path(anchor: "pb-main-file")
    assert_not activity.reload.active?
    assert BliActivity.current_import.exists?(activity.id)
    assert_not BliActivity.active.exists?(activity.id)
    assert BliActivity.disabled.exists?(activity.id)
  end

  test "parent activity mapping disables without deleting mapped row" do
    employee = Employee.create!(employee_code: "1004", name: "Mapping Employee")
    vertical = VerticalPercent.create!(vertical_name: "Mapped Vertical", total: 100)
    mapping = ParentActivityAssignment.create!(
      employee: employee,
      vertical_percent: vertical,
      source_parent_activity: "Mapped Parent"
    )

    get admin_pb_imports_path
    assert_response :success
    assert_select "h2", "Parent Activity Mapping Data"
    assert_includes response.body, "Mapped Parent"

    patch admin_toggle_parent_activity_assignment_path(mapping)

    assert_redirected_to admin_pb_imports_path(anchor: "parent-activity-mapping")
    assert_not mapping.reload.active?
    assert ParentActivityAssignment.exists?(mapping.id)
  end

  test "pb source sync archives old rows without deleting plan submission history" do
    employee = Employee.create!(employee_code: "1005", name: "Sync Employee")
    old_activity = BliActivity.create!(
      employee: employee,
      project_name: "Old Project",
      vertical_name: "Old Vertical",
      activity_name: "Old Activity",
      responsible_user_name: employee.name,
      allocated_fund: 75
    )
    submission = PlanSubmission.create!(
      employee: employee,
      mode: "project",
      filter_name: "Old Project",
      original_total: 75,
      changed_total: 75,
      submitted_at: Time.current
    )
    item = PlanSubmissionItem.create!(
      plan_submission: submission,
      bli_activity: old_activity,
      original_fund: 75,
      changed_fund: 75
    )

    file = Tempfile.new([ "pb-source", ".csv" ])
    file.write([
      "Financial Year,Parent Activity,Responsible Users,Project Name,Activity,BLI Allocated Fund",
      "2026-2027,New Vertical,Sync Employee,New Project,New Activity,120"
    ].join("\n"))
    file.close

    BliActivitySync.new(source_path: file.path, save_history: false).call

    assert PlanSubmission.exists?(submission.id)
    assert PlanSubmissionItem.exists?(item.id)
    assert_equal 1, old_activity.reload.import_flag
    assert_not old_activity.active?
    assert BliActivity.active.where(project_name: "New Project").exists?
  ensure
    file&.unlink
  end

  test "action plan json apis return project and vertical rows" do
    ActionPlanRow.create!(
      po_id: "PO-API",
      project_name: "API Project",
      project_id: "PO-API",
      user_id: "101",
      user_name: "API FCO",
      to_id: "201",
      to_name: "API TO",
      statte: "MP",
      asa_theme_id: "1",
      asa_theme: "API Theme",
      asa_activity_id: "1.1",
      asa_activity_name: "API Activity",
      apr: 4,
      apr_t: 2,
      planned_total: 4
    )

    get api_project_action_plan_path, params: { project: "API Project", period: "monthly", period_month: "apr" }
    assert_response :success
    project_payload = JSON.parse(response.body)
    assert_equal "project", project_payload["plan_type"]
    assert_equal 1, project_payload["summary"]["row_count"]
    assert_equal "API Project", project_payload["rows"].first["project_name"]

    get api_vertical_action_plan_path, params: { project: "API Project", period: "monthly", period_month: "apr" }
    assert_response :success
    vertical_payload = JSON.parse(response.body)
    assert_equal "vertical", vertical_payload["plan_type"]
    assert_equal 1, vertical_payload["summary"]["row_count"]
    assert_equal 4, vertical_payload["rows"].first["months"]["apr"]["target"]
  end
end

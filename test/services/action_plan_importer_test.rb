require "test_helper"
require "csv"

class ActionPlanImporterTest < ActiveSupport::TestCase
  test "imports downloaded action plan file that has project id instead of po id" do
    file = Tempfile.new([ "downloaded_action_plan", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "Project_ID", "Project", "FCO ID", "Apr Target", "Apr Achievement" ]
      csv << [ "PO-2", "Downloaded Project", "FCO-9", "12", "5" ]
    end)
    file.close

    result = ActionPlanImporter.new(action_plan_file: file.path).import!

    row = ActionPlanRow.active_import.find_by!(project_name: "Downloaded Project")
    assert_equal 1, result[:action_plan_rows]
    assert_equal "PO-2", row.po_id
    assert_equal "PO-2", row.project_id
    assert_equal 12, row.apr
    assert_equal 5, row.apr_t
  ensure
    file&.unlink
  end

  test "empty action plan import does not archive existing active rows" do
    ActionPlanRow.create!(po_id: "PO-1", project_name: "Existing Project")
    file = Tempfile.new([ "empty_action_plan", ".csv" ])
    file.write(CSV.generate { |csv| csv << [ "Wrong", "Headers" ] })
    file.close

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ActionPlanImporter.new(action_plan_file: file.path).import!
    end

    assert_match "No action plan rows found", error.message
    assert_equal 1, ActionPlanRow.active_import.count
    assert_equal 0, ActionPlanRow.where(import_flag: 1).count
  ensure
    file&.unlink
  end

  test "append action plan import only inserts new rows" do
    ActionPlanRow.create!(
      po_id: "PO-1",
      project_name: "Existing Project",
      statte: "MP",
      user_id: "FCO-1",
      to_id: "TO-1",
      asa_theme_id: "4",
      asa_activity_id: "4.1",
      apr: 7,
      original_apr: 7
    )
    file = Tempfile.new([ "append_action_plan", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "PO_ID", "State", "Project", "FCO ID", "TO_ID", "ASA_Theme_ID", "ASA_Activity_ID", "Apr Target" ]
      csv << [ "PO-1", "MP", "Existing Project", "FCO-1", "TO-1", "4", "4.1", "99" ]
      csv << [ "PO-2", "MP", "New Project", "FCO-2", "TO-2", "4", "4.2", "12" ]
    end)
    file.close

    result = ActionPlanImporter.new(action_plan_file: file.path, action_plan_import_mode: "append").import!

    assert_equal 1, result[:action_plan_rows]
    assert_equal 2, ActionPlanRow.active_import.count
    assert_equal 7, ActionPlanRow.active_import.find_by!(project_name: "Existing Project").apr
    assert_equal 12, ActionPlanRow.active_import.find_by!(project_name: "New Project").apr
  ensure
    file&.unlink
  end

  test "update action plan import only changes matching rows" do
    existing = ActionPlanRow.create!(
      po_id: "PO-1",
      project_name: "Existing Project",
      statte: "MP",
      user_id: "FCO-1",
      to_id: "TO-1",
      asa_theme_id: "4",
      asa_activity_id: "4.1",
      apr: 7,
      original_apr: 7
    )
    file = Tempfile.new([ "update_action_plan", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "PO_ID", "State", "Project", "FCO ID", "TO_ID", "ASA_Theme_ID", "ASA_Activity_ID", "Apr Target" ]
      csv << [ "PO-1", "MP", "Existing Project", "FCO-1", "TO-1", "4", "4.1", "22" ]
      csv << [ "PO-2", "MP", "New Project", "FCO-2", "TO-2", "4", "4.2", "12" ]
    end)
    file.close

    result = ActionPlanImporter.new(action_plan_file: file.path, action_plan_import_mode: "update").import!

    assert_equal 1, result[:action_plan_rows]
    assert_equal 1, ActionPlanRow.active_import.count
    assert_equal 22, existing.reload.apr
    assert_equal 22, existing.original_apr
  ensure
    file&.unlink
  end

  test "merge action plan import updates matching rows and inserts new rows" do
    existing = ActionPlanRow.create!(
      po_id: "PO-1",
      project_name: "Existing Project",
      statte: "MP",
      user_id: "FCO-1",
      to_id: "TO-1",
      asa_theme_id: "4",
      asa_activity_id: "4.1",
      apr: 7,
      original_apr: 7
    )
    untouched = ActionPlanRow.create!(
      po_id: "PO-X",
      project_name: "Untouched Project",
      statte: "MP",
      user_id: "FCO-X",
      to_id: "TO-X",
      asa_theme_id: "4",
      asa_activity_id: "4.9",
      apr: 3,
      original_apr: 3
    )
    file = Tempfile.new([ "merge_action_plan", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "PO_ID", "State", "Project", "FCO ID", "TO_ID", "ASA_Theme_ID", "ASA_Activity_ID", "Apr Target" ]
      csv << [ "PO-1", "MP", "Existing Project", "FCO-1", "TO-1", "4", "4.1", "22" ]
      csv << [ "PO-2", "MP", "New Project", "FCO-2", "TO-2", "4", "4.2", "12" ]
    end)
    file.close

    result = ActionPlanImporter.new(action_plan_file: file.path, action_plan_import_mode: "merge").import!

    assert_equal 2, result[:action_plan_rows]
    assert_equal 3, ActionPlanRow.active_import.count
    assert_equal 22, existing.reload.apr
    assert_equal 22, existing.original_apr
    assert_equal 3, untouched.reload.apr
    assert_equal 12, ActionPlanRow.active_import.find_by!(project_name: "New Project").apr
  ensure
    file&.unlink
  end

  test "project owner partial import does not disable omitted rows" do
    Employee.create!(employee_code: "9999", name: "Changed Owner", email: "changed@example.org")
    ProjectOwnership.create!(po_id: "PO-1", project_name: "Existing Project", project_owner_id: "1001")
    omitted = ProjectOwnership.create!(po_id: "PO-2", project_name: "Omitted Project", project_owner_id: "1002")
    file = Tempfile.new([ "project_owner_partial", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "PO_ID", "Project", "Project_owner_id", "PO_Name", "Email_Id" ]
      csv << [ "PO-1", "Existing Project", "9999", "Changed Owner", "changed@example.org" ]
    end)
    file.close

    result = ActionPlanImporter.new(project_file: file.path).import!

    assert_equal 1, result[:project_ownerships]
    assert_equal "9999", ProjectOwnership.find_by!(po_id: "PO-1", project_name: "Existing Project").project_owner_id
    assert omitted.reload.active?
  ensure
    file&.unlink
  end

  test "vertical mapping partial import does not disable omitted rows" do
    employee = Employee.create!(employee_code: "1079", name: "Abhishek Mishra")
    ActionPlanVerticalMapping.create!(
      employee: employee,
      employee_code: employee.employee_code,
      state_code: "MP",
      asa_theme_id: "13",
      asa_theme: "Old Theme"
    )
    omitted = ActionPlanVerticalMapping.create!(
      employee_code: "2001",
      state_code: "JH",
      asa_theme_id: "16",
      asa_theme: "Omitted Theme"
    )
    file = Tempfile.new([ "vertical_mapping_partial", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "State", "ASA_Theme_ID", "ASA_Theme", "emp_name", "emp_id" ]
      csv << [ "MP", "13", "Changed Theme", employee.name, employee.employee_code ]
    end)
    file.close

    result = ActionPlanImporter.new(vertical_mapping_file: file.path).import!

    assert_equal 1, result[:vertical_mappings]
    assert_equal "Changed Theme", ActionPlanVerticalMapping.find_by!(employee_code: employee.employee_code, state_code: "MP", asa_theme_id: "13").asa_theme
    assert omitted.reload.active?
  ensure
    file&.unlink
  end

  test "replace import carries pending month changes forward" do
    ActionPlanRow.create!(
      po_id: "PO-1",
      project_name: "Existing Project",
      statte: "MP",
      user_id: "FCO-1",
      to_id: "TO-1",
      asa_theme_id: "4",
      asa_activity_id: "4.1",
      apr: 15,
      original_apr: 10
    )
    file = Tempfile.new([ "replace_action_plan", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "PO_ID", "State", "Project", "FCO ID", "TO_ID", "ASA_Theme_ID", "ASA_Activity_ID", "Apr Target" ]
      csv << [ "PO-1", "MP", "Existing Project", "FCO-1", "TO-1", "4", "4.1", "11" ]
    end)
    file.close

    result = ActionPlanImporter.new(action_plan_file: file.path).import!
    row = ActionPlanRow.active_import.find_by!(project_name: "Existing Project")

    assert_equal 1, result[:preserved_changes]
    assert_equal 15, row.apr
    assert_equal 11, row.original_apr
    assert_equal 4, row.apr - row.original_apr
  ensure
    file&.unlink
  end

  test "imports exported action plan workbook" do
    ActionPlanRow.create!(
      po_id: "PO-1",
      project_id: "PO-1",
      project_name: "Exported Project",
      statte: "MP",
      user_id: "FCO-1",
      to_id: "TO-1",
      asa_theme_id: "4",
      asa_activity_id: "4.1",
      apr: 7,
      original_apr: 7,
      planned_total: 7
    )
    file = Tempfile.new([ "exported_action_plan", ".xlsx" ])
    file.binmode
    file.write(XlsxWorkbook.from_csv(ActionPlanExporter.active_csv, title: "Action Plan", sheet_name: "Action Plan"))
    file.close

    result = ActionPlanImporter.new(action_plan_file: file.path, action_plan_import_mode: "replace").import!

    assert_equal 1, result[:action_plan_rows]
    row = ActionPlanRow.active_import.find_by!(project_name: "Exported Project")
    assert_equal "PO-1", row.po_id
    assert_equal 7, row.apr
  ensure
    file&.unlink
  end

  test "imports exported project ownership workbook" do
    employee = Employee.create!(employee_code: "1001", name: "Project Owner", email: "owner@example.org")
    ProjectOwnership.create!(
      po_id: "PO-1",
      project_name: "Owned Project",
      project_owner_id: employee.employee_code,
      po_name: employee.name,
      email_id: employee.email
    )
    file = Tempfile.new([ "exported_project_owners", ".xlsx" ])
    file.binmode
    file.write(XlsxWorkbook.from_csv(ActionPlanExporter.project_ownerships_csv, title: "Project Owners", sheet_name: "Project Owners"))
    file.close
    ProjectOwnership.update_all(active: false)

    result = ActionPlanImporter.new(project_file: file.path).import!

    assert_equal 1, result[:project_ownerships]
    ownership = ProjectOwnership.find_by!(po_id: "PO-1", project_name: "Owned Project")
    assert ownership.active?
    assert_equal employee.employee_code, ownership.project_owner_id
  ensure
    file&.unlink
  end

  test "imports exported user vertical mapping workbook" do
    employee = Employee.create!(employee_code: "1079", name: "Abhishek Mishra", active: false)
    ActionPlanVerticalMapping.create!(
      employee: employee,
      employee_code: employee.employee_code,
      state_code: "MP",
      asa_theme_id: "13",
      asa_theme: "Basic Services and Sanitation"
    )
    file = Tempfile.new([ "exported_vertical_mapping", ".xlsx" ])
    file.binmode
    file.write(XlsxWorkbook.from_csv(ActionPlanExporter.vertical_mappings_csv, title: "User Vertical Mapping", sheet_name: "User Verticals"))
    file.close
    ActionPlanVerticalMapping.update_all(active: false)

    result = ActionPlanImporter.new(vertical_mapping_file: file.path).import!

    assert_equal 1, result[:vertical_mappings]
    mapping = ActionPlanVerticalMapping.find_by!(
      employee_code: employee.employee_code,
      state_code: "MP",
      asa_theme_id: "13"
    )
    assert mapping.active?
    assert_equal employee, mapping.employee
    assert employee.reload.active?
    assert User.exists?(login: employee.employee_code)
  ensure
    file&.unlink
  end
end

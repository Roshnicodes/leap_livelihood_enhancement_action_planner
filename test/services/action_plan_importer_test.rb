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
end

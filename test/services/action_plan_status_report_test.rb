require "test_helper"

class ActionPlanStatusReportTest < ActiveSupport::TestCase
  test "fco id 28 is labeled as Financial Inclusion even when imported name is wrong" do
    ActionPlanRow.create!(
      po_id: "PO-FI",
      project_name: "Financial Inclusion",
      statte: "OD",
      user_id: "28",
      user_name: "Betul-FCO",
      apr: 1,
      planned_total: 1
    )

    report_row = ActionPlanStatusReport.new.fco_submission_rows.find { |row| row[:fco_ids] == [ "28" ] }

    assert_equal "Financial Inclusion", ActionPlanFcoGroup.name_for("28", "Betul-FCO")
    assert_equal "Financial Inclusion", report_row[:fco_name]
  end
end

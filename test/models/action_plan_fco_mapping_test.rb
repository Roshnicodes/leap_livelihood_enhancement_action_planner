require "test_helper"
require "tempfile"

class ActionPlanFcoMappingTest < ActiveSupport::TestCase
  test "action plan fco options are grouped by canonical fco id" do
    ActionPlanRow.create!(
      po_id: "PO-1",
      project_name: "Betul Project",
      user_id: "7",
      user_name: "Betul-FCO"
    )
    ActionPlanRow.create!(
      po_id: "PO-2",
      project_name: "Financial Inclusion Project",
      user_id: "28",
      user_name: "Betul-FCO"
    )
    ActionPlanRow.create!(
      po_id: "PO-3",
      project_name: "Financial Inclusion Project 2",
      user_id: "28",
      user_name: "Pakur - FCO"
    )

    fcos = ActionPlanFcoMapping.action_plan_fcos

    assert_equal 1, fcos.count { |fco| fco[:fco_id] == "28" }
    assert_includes fcos, { fco_id: "7", fco_name: "Betul-FCO", fco_ids: [ "7" ] }
    assert_includes fcos, { fco_id: "28", fco_name: "Financial Inclusion", fco_ids: [ "28" ] }
    assert_not_includes fcos.map { |fco| [ fco[:fco_id], fco[:fco_name] ] }, [ "28", "Betul-FCO" ]
  end

  test "mapping import saves grouped fcos with canonical name" do
    employee = Employee.create!(employee_code: "1726", name: "Abhay Gupta")
    ActionPlanRow.create!(
      po_id: "PO-4",
      project_name: "Financial Inclusion Project",
      user_id: "28",
      user_name: "Pakur - FCO"
    )

    file = Tempfile.new([ "fco-mapping", ".csv" ])
    file.write([
      "Employee Code,FCO ID,FCO Name",
      "1726,28.0,Pakur - FCO"
    ].join("\n"))
    file.close

    result = ActionPlanFcoMapping.import_file!(file.path)
    mapping = ActionPlanFcoMapping.find_by!(employee: employee)

    assert_equal 1, result[:imported]
    assert_equal "28", mapping.fco_id
    assert_equal "Financial Inclusion", mapping.fco_name
  ensure
    file&.unlink
  end
end

require "test_helper"

class ActionPlanSplitEntityRepairTest < ActiveSupport::TestCase
  test "joins text split at &amp; back together and leaves FCO and months untouched" do
    land_row = create_row(
      theme_id: "5", theme: "Land &amp", activity_id: "amp", activity: "Water Resources Development - Own Fund",
      unit_type: "5.2", a_remark: "Construction &amp"
    )
    organic_row = create_row(
      theme_id: "3", theme: "Organic/Natural Farming", activity_id: "3.6",
      activity: "FLD and PVSP Report submitted to M&amp", unit_type: "E", a_remark: "No."
    )
    clean_row = create_row(theme_id: "2", theme: "Training & Gender", activity_id: "2.1", activity: "Village Coverage", unit_type: "No.")

    assert_no_changes -> { [ land_row.reload.theme, organic_row.reload.activity ] } do
      ActionPlanSplitEntityRepair.call
    end

    changes = ActionPlanSplitEntityRepair.call(apply: true)

    assert_equal [ land_row.id, organic_row.id ].sort, changes.map { |row, _| row.id }.sort
    land_row.reload
    assert_equal "Land & Water Resources Development - Own Fund", land_row.theme
    assert_equal "5.2", land_row.activity_id
    assert_equal "Construction & Rennovation of Stop Dam", land_row.activity
    assert_equal "No", land_row.unit_type
    assert_nil land_row.a_remark
    assert_equal "Shahdol-FCO", land_row.user_name
    assert_equal 25, land_row.may

    organic_row.reload
    assert_equal "FLD and PVSP Report submitted to M&E", organic_row.activity
    assert_equal "No.", organic_row.unit_type
    assert_equal "Village Coverage", clean_row.reload.activity
    assert_empty ActionPlanSplitEntityRepair.call(apply: true)
  end

  private

  def create_row(**attributes)
    ActionPlanRow.create!(
      po_id: "2", project_id: "2", project_name: "Walmart Foundation-2", statte: "MP",
      user_id: "40", user_name: "Shahdol-FCO", import_flag: 0, active: true, may: 25,
      **attributes
    )
  end
end

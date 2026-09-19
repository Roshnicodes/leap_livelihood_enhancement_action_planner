require "test_helper"

class ActionPlanRowTest < ActiveSupport::TestCase
  test "display columns can hide fco and to dimensions" do
    attributes = ActionPlanRow.display_columns(admin: true, without_fco: true, without_to: true).map { |column| column[:attribute] }

    assert_not_includes attributes, :user_id
    assert_not_includes attributes, :user_name
    assert_not_includes attributes, :to_id
    assert_not_includes attributes, :to_name
    assert_includes attributes, :asa_activity_id
    assert_includes attributes, :project_name
  end

  test "grouped display rows sum totals while hiding selected dimensions" do
    first = create_action_plan_row(
      user_id: "9",
      user_name: "Ambikapur - FCO",
      to_id: "89",
      to_name: "Sitapur - TO",
      apr: 2,
      apr_t: 1.5,
      original_apr: 2,
      planned_total: 2
    )
    second = create_action_plan_row(
      user_id: "10",
      user_name: "Other FCO",
      to_id: "89",
      to_name: "Sitapur - TO",
      apr: 3,
      apr_t: 2.25,
      original_apr: 3,
      planned_total: 3
    )

    grouped = ActionPlanRow.grouped_for_display(
      ActionPlanRow.where(id: [ first.id, second.id ]).order(:id),
      without_fco: true
    )

    assert_equal 1, grouped.size
    row = grouped.first
    assert_nil row.user_id
    assert_nil row.user_name
    assert_equal "89", row.to_id
    assert_equal "Sitapur - TO", row.to_name
    assert_equal 5, row.apr
    assert_equal 5, row.original_apr
    assert_equal 5, row.planned_total
    assert_equal BigDecimal("3.75"), row.apr_t
  end

  private

  def create_action_plan_row(attributes)
    ActionPlanRow.create!(
      {
        po_id: "PO-1",
        project_id: "21",
        project_name: "Ashraya Hastha Trust",
        statte: "CG",
        asa_theme_id: "1",
        asa_theme: "Programme Coverage",
        asa_activity_id: "1.2",
        asa_activity_name: "Coverage",
        theme_id: "T1",
        theme: "Project Theme",
        activity_id: "3.1",
        activity: "Project Activity",
        unit_type: "Count"
      }.merge(attributes)
    )
  end
end

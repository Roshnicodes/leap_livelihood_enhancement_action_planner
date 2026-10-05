require "test_helper"

class ActionPlanFcoTransferServiceTest < ActiveSupport::TestCase
  setup do
    ActionPlanFcoTransfer.reset_resolution_cache!
    @admin = User.create!(login: "fco-transfer-admin", role: "admin", password: "secret")
    @target_employee = Employee.create!(employee_code: "FCO-TARGET", name: "Target FCO Employee", active: true)
    ActionPlanFcoMapping.create!(
      employee: @target_employee,
      employee_code: @target_employee.employee_code,
      fco_id: "TARGET",
      fco_name: "Target FCO"
    )
  end

  teardown do
    ActionPlanFcoTransfer.reset_resolution_cache!
  end

  test "moves current source rows, keeps history intact, and makes source submissions visible under target" do
    source_row = create_action_plan_row("SOURCE", "Source FCO", "Transferred Project", po_id: "PO-SOURCE")
    second_source_row = create_action_plan_row("SOURCE", "Source FCO", "Second Transferred Project", po_id: "PO-SOURCE-2")
    target_row = create_action_plan_row("TARGET", "Target FCO", "Existing Target Project", po_id: "PO-TARGET")
    archived_source_row = create_action_plan_row("SOURCE", "Source FCO", "Archived Source Project", po_id: "PO-ARCHIVED", import_flag: 1)
    month_change = create_month_change(source_row)
    historical_submission = create_historical_submission("SOURCE", "Source FCO", "Transferred Project", "PO-SOURCE")

    transfer = ActionPlanFcoTransferService.new(
      source_fco_id: "SOURCE",
      target_fco_id: "TARGET",
      transferred_by: @admin,
      note: "Source FCO merged into Target FCO"
    ).call

    assert_equal "TARGET", source_row.reload.user_id
    assert_equal "Target FCO", source_row.user_name
    assert_equal "TARGET", second_source_row.reload.user_id
    assert_equal "SOURCE", archived_source_row.reload.user_id
    assert_equal "TARGET", month_change.reload.user_id
    assert_equal "SOURCE", historical_submission.reload.fco_id
    assert_equal 2, transfer.action_plan_row_count
    assert_equal 2, transfer.project_count
    assert_equal [ source_row.id, second_source_row.id ].sort, transfer.action_plan_row_ids.map(&:to_i).sort
    assert_equal [ month_change.id ], transfer.month_change_ids.map(&:to_i)
    assert_equal "TARGET", ActionPlanFcoGroup.canonical_id("SOURCE")
    assert_includes ActionPlanFcoGroup.ids_for("TARGET"), "SOURCE"

    report_row = ActionPlanStatusReport.new.fco_submission_rows.find do |row|
      row[:fco_ids].include?("TARGET")
    end
    april = report_row[:month_details]["apr"]

    assert_equal 3, april[:expected_count]
    assert_equal 1, april[:submitted_count]

    assert_equal "TARGET", target_row.reload.user_id

    ActionPlanVerticalMapping.create!(
      employee: @target_employee,
      employee_code: @target_employee.employee_code,
      state_code: "MP",
      asa_theme_id: "1",
      asa_theme: "Test Theme"
    )
    create_historical_submission("TARGET", "Target FCO", "Existing Target Project", "PO-TARGET")

    vertical_summary = ActionPlanStatusReport.new.vertical_summary_rows.find do |row|
      row[:state] == "MP" && row[:asa_theme_id] == "1"
    end

    assert_equal 1, vertical_summary[:approved_fco]
  end

  test "reverts only the exact rows and active month changes captured by the transfer" do
    source_row = create_action_plan_row("SOURCE", "Source FCO", "Transferred Project", po_id: "PO-SOURCE")
    month_change = create_month_change(source_row)
    create_action_plan_row("TARGET", "Target FCO", "Existing Target Project", po_id: "PO-TARGET")

    transfer = ActionPlanFcoTransferService.new(
      source_fco_id: "SOURCE",
      target_fco_id: "TARGET",
      transferred_by: @admin
    ).call

    ActionPlanFcoTransferService.revert!(transfer: transfer, reverted_by: @admin)

    assert_equal "SOURCE", source_row.reload.user_id
    assert_equal "Source FCO", source_row.user_name
    assert_equal "SOURCE", month_change.reload.user_id
    assert_not transfer.reload.active?
    assert_equal @admin, transfer.reverted_by
    assert_equal "SOURCE", ActionPlanFcoGroup.canonical_id("SOURCE")
    assert_not_includes ActionPlanFcoGroup.ids_for("TARGET"), "SOURCE"
  end

  test "does not move anything when an active month change would collide with target data" do
    source_row = create_action_plan_row("SOURCE", "Source FCO", "Shared Project", po_id: "PO-SHARED")
    create_action_plan_row("TARGET", "Target FCO", "Shared Project", po_id: "PO-SHARED")
    source_change = create_month_change(source_row)
    target_change = ActionPlanMonthChange.create!(
      po_id: source_change.po_id,
      project_name: source_change.project_name,
      statte: source_change.statte,
      user_id: "TARGET",
      to_id: source_change.to_id,
      asa_theme_id: source_change.asa_theme_id,
      asa_activity_id: source_change.asa_activity_id,
      month: source_change.month,
      original_value: source_change.original_value,
      changed_value: 7,
      status: "pending"
    )

    error = assert_raises(ActionPlanFcoTransferService::TransferError) do
      ActionPlanFcoTransferService.new(
        source_fco_id: "SOURCE",
        target_fco_id: "TARGET",
        transferred_by: @admin
      ).call
    end

    assert_match(/conflicts with the target FCO/, error.message)
    assert_equal "SOURCE", source_row.reload.user_id
    assert_equal "SOURCE", source_change.reload.user_id
    assert_equal "TARGET", target_change.reload.user_id
    assert_equal 0, ActionPlanFcoTransfer.count
  end

  private

  def create_action_plan_row(fco_id, fco_name, project_name, po_id:, import_flag: 0)
    ActionPlanRow.create!(
      po_id: po_id,
      project_name: project_name,
      statte: "MP",
      user_id: fco_id,
      user_name: fco_name,
      to_id: "TO-1",
      to_name: "TO One",
      asa_theme_id: "1",
      asa_activity_id: "1.1",
      apr: 2,
      original_apr: 2,
      planned_total: 2,
      import_flag: import_flag,
      active: true
    )
  end

  def create_month_change(row)
    ActionPlanMonthChange.create!(
      po_id: row.po_id,
      project_name: row.project_name,
      statte: row.statte,
      user_id: row.user_id,
      to_id: row.to_id,
      asa_theme_id: row.asa_theme_id,
      asa_activity_id: row.asa_activity_id,
      month: "apr",
      original_value: 2,
      changed_value: 3,
      status: "pending"
    )
  end

  def create_historical_submission(fco_id, fco_name, project_name, po_id)
    AchievementSubmission.create!(
      employee: @target_employee,
      fco_id: fco_id,
      fco_name: fco_name,
      to_id: "TO-1",
      to_name: "TO One",
      project_name: project_name,
      po_id: po_id,
      state_code: "MP",
      asa_theme_id: "1",
      month: "apr",
      status: "approved",
      current_stage: "complete",
      submitted_at: Time.current,
      mis_submitted: false
    )
  end
end

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

  test "jamtara and pakur fco ids keep their separate canonical labels" do
    ActionPlanRow.create!(
      po_id: "PO-JAM-18",
      project_name: "Jamtara Project 18",
      statte: "JH",
      user_id: "18",
      user_name: "Pakur - FCO",
      apr: 1,
      planned_total: 1
    )
    ActionPlanRow.create!(
      po_id: "PO-JAM-19",
      project_name: "Pakur Project 19",
      statte: "JH",
      user_id: "19",
      user_name: "Pakur - FCO",
      apr: 1,
      planned_total: 1
    )

    report_rows = ActionPlanStatusReport.new.fco_submission_rows
    jamtara_rows = report_rows.select { |row| row[:fco_name] == "Jamtara - FCO" }
    pakur_rows = report_rows.select { |row| row[:fco_name] == "Pakur - FCO" }

    assert_equal "Jamtara - FCO", ActionPlanFcoGroup.name_for("18", "Pakur - FCO")
    assert_equal "Pakur - FCO", ActionPlanFcoGroup.name_for("19", "Jamtara - FCO")
    assert_equal [ [ "18" ] ], jamtara_rows.map { |row| row[:fco_ids] }
    assert_equal [ [ "19" ] ], pakur_rows.map { |row| row[:fco_ids] }
  end

  test "action plan report ignores achievement submissions created by mis" do
    employee = Employee.create!(employee_code: "FCO-RPT", name: "Report FCO", active: true)
    ActionPlanRow.create!(
      po_id: "PO-RPT",
      project_name: "Report Project",
      statte: "MP",
      user_id: "9",
      user_name: "Report FCO",
      to_id: "TO-RPT",
      to_name: "Report TO",
      asa_theme_id: "1",
      apr: 1,
      planned_total: 1
    )
    AchievementSubmission.create!(
      employee: employee,
      fco_id: "9",
      fco_name: "Report FCO",
      to_id: "TO-RPT",
      to_name: "Report TO",
      project_name: "Report Project",
      po_id: "PO-RPT",
      state_code: "MP",
      asa_theme_id: "1",
      month: "apr",
      status: "approved",
      current_stage: "complete",
      submitted_at: Time.current,
      mis_submitted: true
    )

    report = ActionPlanStatusReport.new
    report_row = report.fco_submission_rows.find { |row| row[:fco_ids] == [ "9" ] }

    assert_equal "Not Submitted", report_row[:month_details]["apr"][:status]
    assert_equal 0, report.summary_totals[:submitted]
    assert_empty report.achievement_detail_rows
  end

  test "action plan report includes achievement submissions created by fco" do
    employee = Employee.create!(employee_code: "FCO-RPT-2", name: "Report FCO 2", active: true)
    row = ActionPlanRow.create!(
      po_id: "PO-RPT-2",
      project_name: "Report Project 2",
      statte: "MP",
      user_id: "10",
      user_name: "Report FCO 2",
      to_id: "TO-RPT-2",
      to_name: "Report TO 2",
      asa_theme_id: "1",
      apr: 1,
      planned_total: 1
    )
    submission = AchievementSubmission.create!(
      employee: employee,
      fco_id: "10",
      fco_name: "Report FCO 2",
      to_id: "TO-RPT-2",
      to_name: "Report TO 2",
      project_name: "Report Project 2",
      po_id: "PO-RPT-2",
      state_code: "MP",
      asa_theme_id: "1",
      month: "apr",
      status: "approved",
      current_stage: "complete",
      submitted_at: Time.current,
      mis_submitted: false
    )
    submission.achievement_submission_rows.create!(
      action_plan_row: row,
      month: "apr",
      target_value: 1,
      achievement_value: 1
    )

    report = ActionPlanStatusReport.new
    report_row = report.fco_submission_rows.find { |row| row[:fco_ids] == [ "10" ] }

    assert_equal "Submitted", report_row[:month_details]["apr"][:status]
    assert_equal 1, report.summary_totals[:submitted]
    assert_equal [ "Report Project 2" ], report.achievement_detail_rows.map { |detail| detail[:project] }
  end

  test "fco submission rows show one row for each canonical fco" do
    ActionPlanRow.create!(
      po_id: "PO-FI-1",
      project_name: "Financial Inclusion MP",
      statte: "MP",
      user_id: "28",
      user_name: "Betul-FCO",
      apr: 1,
      planned_total: 1
    )
    ActionPlanRow.create!(
      po_id: "PO-FI-2",
      project_name: "Financial Inclusion JH",
      statte: "JH",
      user_id: "28",
      user_name: "Pakur - FCO",
      may: 1,
      planned_total: 1
    )

    report_rows = ActionPlanStatusReport.new.fco_submission_rows
    financial_inclusion_rows = report_rows.select { |row| row[:fco_ids] == [ "28" ] }

    assert_equal 1, financial_inclusion_rows.size
    assert_equal "JH, MP", financial_inclusion_rows.first[:state]
    assert_equal "Financial Inclusion", financial_inclusion_rows.first[:fco_name]
  end

  test "uses an FCO's complete assigned project list for every monthly denominator" do
    employee = Employee.create!(employee_code: "FCO-KOTMA", name: "Kotma FCO", active: true)
    fco_id = "KOTMA-REPORT"

    [ "Kotma Project 1", "Kotma Project 2", "Kotma Project 3", "Kotma Project 4" ].each_with_index do |project_name, index|
      ActionPlanRow.create!(
        po_id: "PO-KOTMA-#{index}",
        project_name: project_name,
        statte: "MP",
        user_id: fco_id,
        user_name: "Kotma-FCO",
        apr: index < 3 ? 1 : 0,
        jun: index == 3 ? 1 : 0,
        planned_total: 1
      )
    end

    [ "Kotma Project 1", "Kotma Project 2", "Kotma Project 3" ].each_with_index do |project_name, index|
      AchievementSubmission.create!(
        employee: employee,
        fco_id: fco_id,
        fco_name: "Kotma-FCO",
        to_id: "TO-KOTMA",
        to_name: "Kotma TO",
        project_name: project_name,
        po_id: "PO-KOTMA-#{index}",
        state_code: "MP",
        asa_theme_id: "1",
        month: "apr",
        status: "approved",
        current_stage: "complete",
        submitted_at: Time.current,
        mis_submitted: false
      )
    end

    report = ActionPlanStatusReport.new
    row = report.fco_submission_rows.find { |item| item[:fco_ids] == [ fco_id ] }
    april = row[:month_details]["apr"]
    june = row[:month_details]["jun"]

    assert_equal 4, row[:project_count]
    assert_equal 4, april[:expected_count]
    assert_equal 3, april[:submitted_count]
    assert_equal "Partial", april[:status]
    assert_equal [ "Kotma Project 4" ], april[:not_submitted_projects]
    assert_equal 4, june[:expected_count]
    assert_equal "Not Submitted", june[:status]
    assert_equal 3, report.summary_totals[:submitted]
  end

  test "approval grid aggregates every project for the FCO month" do
    employee = Employee.create!(employee_code: "FCO-APPROVAL", name: "Approval FCO", active: true)
    fco_id = "APPROVAL-REPORT"

    [ "Approved Project", "Pending Project", "Returned Project", "Unsubmitted Project" ].each_with_index do |project_name, index|
      ActionPlanRow.create!(
        po_id: "PO-APPROVAL-#{index}",
        project_name: project_name,
        statte: "MP",
        user_id: fco_id,
        user_name: "Approval-FCO",
        apr: 1,
        planned_total: 1
      )
    end

    approved_submission = AchievementSubmission.create!(
      employee: employee,
      fco_id: fco_id,
      fco_name: "Approval-FCO",
      to_id: "TO-APPROVAL",
      to_name: "Approval TO",
      project_name: "Approved Project",
      po_id: "PO-APPROVAL-0",
      state_code: "MP",
      asa_theme_id: "1",
      month: "apr",
      status: "approved",
      current_stage: "complete",
      submitted_at: Time.current,
      mis_submitted: false
    )
    pending_submission = approved_submission.dup
    pending_submission.assign_attributes(project_name: "Pending Project", po_id: "PO-APPROVAL-1", submitted_at: Time.current)
    pending_submission.save!
    pending_submission.update_columns(status: "pending", current_stage: "vertical")

    returned_submission = approved_submission.dup
    returned_submission.assign_attributes(project_name: "Returned Project", po_id: "PO-APPROVAL-2", submitted_at: Time.current)
    returned_submission.update!(status: "returned", current_stage: "vertical")

    approval_detail = ActionPlanStatusReport.new
      .fco_approval_rows
      .find { |item| item[:fco_ids] == [ fco_id ] }
      .fetch(:month_details)
      .fetch("apr")

    assert_equal "Pending 1/4 · 1 Returned", approval_detail[:status]
    assert_equal "pending", approval_detail[:status_kind]
    assert_equal 4, approval_detail[:expected_count]
    assert_equal 2, approval_detail[:submitted_count]
    assert_equal 1, approval_detail[:approved_count]
    assert_equal 1, approval_detail[:pending_count]
    assert_equal 1, approval_detail[:returned_count]
    assert_equal 2, approval_detail[:not_submitted_count]
  end
end

require "test_helper"

class AchievementReturnFlowTest < ActionDispatch::IntegrationTest
  setup do
    @fco = Employee.create!(employee_code: "FCO-RET", name: "Return FCO", active: true)
    @vertical = Employee.create!(employee_code: "VERT-RET", name: "Vertical Reviewer", active: true)
    @other_vertical = Employee.create!(employee_code: "VERT-OPEN", name: "Other Vertical Reviewer", active: true)
    @po = Employee.create!(employee_code: "PO-RET", name: "Project Owner", active: true)
    Employee.create!(employee_code: ActionPlanSubmission::COO_EMPLOYEE_CODE, name: "COO Reviewer", active: true)

    User.create!(login: @fco.employee_code, employee: @fco, password: "secret")
    User.create!(login: @vertical.employee_code, employee: @vertical, password: "secret")

    ActionPlanFcoMapping.create!(
      employee: @fco,
      employee_code: @fco.employee_code,
      fco_id: "16",
      fco_name: "Jobat - FCO"
    )
    ActionPlanVerticalMapping.create!(
      employee: @vertical,
      employee_code: @vertical.employee_code,
      state_code: "MP",
      asa_theme_id: "1",
      asa_theme: "Livelihood"
    )
    ActionPlanVerticalMapping.create!(
      employee: @other_vertical,
      employee_code: @other_vertical.employee_code,
      state_code: "MP",
      asa_theme_id: "2",
      asa_theme: "Health"
    )
    ProjectOwnership.create!(
      po_id: "PO-RET-ID",
      project_name: "Achievement Return Project",
      project_owner_id: @po.employee_code,
      po_name: @po.name
    )
    @row = ActionPlanRow.create!(
      po_id: "PO-RET-ID",
      project_name: "Achievement Return Project",
      user_id: "17",
      user_name: "Jobat Alias FCO",
      to_id: "TO-RET",
      to_name: "Return TO",
      statte: "MP",
      asa_theme_id: "1",
      asa_theme: "Livelihood",
      asa_activity_id: "1.1",
      asa_activity_name: "Goat rearing support",
      activity: "Training completed",
      unit_type: "Nos",
      apr: 5,
      planned_total: 5
    )
    @other_row = ActionPlanRow.create!(
      po_id: "PO-RET-ID",
      project_name: "Achievement Return Project",
      user_id: "17",
      user_name: "Jobat Alias FCO",
      to_id: "TO-RET",
      to_name: "Return TO",
      statte: "MP",
      asa_theme_id: "2",
      asa_theme: "Health",
      asa_activity_id: "2.1",
      asa_activity_name: "Nutrition meeting",
      activity: "Meeting completed",
      unit_type: "Nos",
      apr: 2,
      planned_total: 2
    )
  end

  test "fco sees vertical returned achievement with remark and can resubmit while another group is pending" do
    login_as(@fco)

    patch achievement_entry_path, params: submission_params(achievement: 3, remark: "Initial field note")

    assert_redirected_to achievement_entry_path(to_id: @row.to_id, project: @row.project_name, month: "apr")
    assert_equal 2, AchievementSubmission.count
    submission = AchievementSubmission.find_by!(vertical_approver: @vertical)
    active_sibling = AchievementSubmission.find_by!(vertical_approver: @other_vertical)
    assert_equal "pending", submission.status
    assert_equal @vertical.id, submission.vertical_approver_id
    assert active_sibling.pending?

    delete logout_path
    login_as(@vertical)
    patch return_achievement_path(stage: "vertical", id: submission), params: { approval_remark: "Please correct evidence" }

    assert_redirected_to achievement_approvals_path(stage: "vertical")
    assert submission.reload.returned?
    assert_equal "Please correct evidence", submission.returned_remark

    delete logout_path
    login_as(@fco)
    get achievement_entry_path

    assert_response :success
    assert_select ".achievement-return-panel"
    assert_includes response.body, "Achievement Return Project"
    assert_includes response.body, "Please correct evidence"
    assert_select "a.achievement-open-return-link[href=?][data-open-returned-achievement-modal]", achievement_entry_path(to_id: @row.to_id, project: @row.project_name, month: "apr"), 1
    assert_select ".achievement-return-entry-modal", 1
    assert_select ".achievement-return-entry-modal input[name=?][value=?]", "to_id", @row.to_id
    assert_select ".achievement-return-entry-modal input[name=?][value=?]", "project", @row.project_name
    assert_select ".achievement-return-entry-modal input[name=?][value=?]", "month", "apr"
    assert_select ".achievement-return-entry-modal input[name=?]", "achievements[#{@row.id}]"
    assert_select ".achievement-return-entry-modal textarea[name=?]", "remarks[#{@row.id}]"
    assert_select ".achievement-return-entry-modal input[type='submit'][value='Submit for Approval'][disabled]", 0

    get achievement_entry_records_path(status: "returned")

    assert_response :success
    assert_includes response.body, "Achievement Return Project"
    assert_includes response.body, "Returned"

    get achievement_entry_path(to_id: @row.to_id, project: @row.project_name, month: "apr")

    assert_response :success
    assert_select ".achievement-return-alert", text: /Please correct evidence/
    assert_select "input[type='submit'][value='Submit for Approval'][disabled]", 0

    assert_difference -> { AchievementSubmission.count }, 1 do
      patch achievement_entry_path, params: submission_params(achievement: 4, remark: "Corrected field note")
    end

    assert_redirected_to achievement_entry_path(to_id: @row.to_id, project: @row.project_name, month: "apr")
    assert_equal 1, AchievementSubmission.where(status: "returned").count
    assert_equal 2, AchievementSubmission.where(status: "pending").count
    new_submission = AchievementSubmission.where.not(id: [ submission.id, active_sibling.id ]).first
    assert_equal [ @row.id ], new_submission.achievement_submission_rows.pluck(:action_plan_row_id)
    assert_equal 4, @row.reload.apr_t

    get achievement_entry_path

    assert_response :success
    assert_select ".achievement-return-panel", 0
  end

  private

  def login_as(employee)
    post login_path, params: { login: employee.employee_code, password: "secret" }
  end

  def submission_params(achievement:, remark:)
    {
      to_id: @row.to_id,
      project: @row.project_name,
      month: "apr",
      achievements: { @row.id.to_s => achievement.to_s, @other_row.id.to_s => "1" },
      remarks: { @row.id.to_s => remark, @other_row.id.to_s => "Sibling pending note" },
      submission_remark: "Please review",
      commit: "Submit for Approval"
    }
  end
end

require "test_helper"
require "csv"

class AchievementMisEditTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-achievement", role: "admin", password: "secret")
    @fco = Employee.create!(employee_code: "FCO-MIS", name: "MIS Edit FCO", active: true)
    @vertical = Employee.create!(employee_code: "VERT-MIS", name: "MIS Vertical Reviewer", active: true)
    @po = Employee.create!(employee_code: "PO-MIS", name: "MIS Project Owner", active: true)
    @coo = Employee.create!(employee_code: ActionPlanSubmission::COO_EMPLOYEE_CODE, name: "COO Reviewer", active: true)

    User.create!(login: @fco.employee_code, employee: @fco, password: "secret")
    User.create!(login: @vertical.employee_code, employee: @vertical, password: "secret")

    ActionPlanFcoMapping.create!(
      employee: @fco,
      employee_code: @fco.employee_code,
      fco_id: "9",
      fco_name: "MIS Edit FCO"
    )
    ActionPlanVerticalMapping.create!(
      employee: @vertical,
      employee_code: @vertical.employee_code,
      state_code: "MP",
      asa_theme_id: "1",
      asa_theme: "Livelihood"
    )
    ProjectOwnership.create!(
      po_id: "PO-MIS-ID",
      project_name: "MIS Achievement Project",
      project_owner_id: @po.employee_code,
      po_name: @po.name
    )
    @row = ActionPlanRow.create!(
      po_id: "PO-MIS-ID",
      project_name: "MIS Achievement Project",
      user_id: "9",
      user_name: "MIS Edit FCO",
      to_id: "TO-MIS",
      to_name: "MIS TO",
      statte: "MP",
      asa_theme_id: "1",
      asa_theme: "Livelihood",
      asa_activity_id: "1.1",
      asa_activity_name: "Field training",
      activity: "Training completed",
      unit_type: "Nos",
      apr: 5,
      apr_t: 3,
      planned_total: 5
    )
  end

  test "mis can open achievement entry and edit an approved achievement for reapproval" do
    approved_submission = create_submission!(
      status: "approved",
      current_stage: "complete",
      vertical_reviewed_at: 3.days.ago,
      po_reviewed_at: 2.days.ago,
      coo_reviewed_at: 1.day.ago
    )
    approved_submission.achievement_submission_rows.create!(
      action_plan_row: @row,
      month: "apr",
      target_value: 5,
      achievement_value: 3
    )

    login_as_admin

    get achievement_entry_records_path(fco_id: "9", period: "monthly", period_month: "apr")

    assert_response :success
    assert_select "a", text: "Edit in Excel Format", count: 0

    get achievement_entry_path(fco_id: "9", to_id: @row.to_id, project: @row.project_name, month: "apr")

    assert_response :success
    assert_select "select[name=fco_id]"
    assert_select "input[name=?]:not([disabled])", "achievements[#{@row.id}]"
    assert_select "input[type='submit'][value='Save Changes']"
    assert_select "form[action=?]", import_excel_achievement_entry_path
    assert_select "input[type='file'][name='achievement_excel_file']"

    assert_difference -> { AchievementSubmission.count }, 1 do
      patch achievement_entry_path,
        params: edit_params(achievement: 4, remark: "Corrected by MIS", commit: "Save Draft")
    end

    assert_redirected_to achievement_entry_path(fco_id: "9", to_id: @row.to_id, project: @row.project_name, month: "apr")
    assert_equal 4, @row.reload.apr_t
    assert approved_submission.reload.approved?

    reapproval = AchievementSubmission.order(:submitted_at, :id).last
    assert_equal "pending", reapproval.status
    assert_equal "vertical", reapproval.current_stage
    assert_equal @fco.id, reapproval.employee_id
    assert_equal @vertical.id, reapproval.vertical_approver_id
    assert_nil reapproval.vertical_reviewed_at
    assert_equal [ 4 ], reapproval.achievement_submission_rows.pluck(:achievement_value)

    delete logout_path
    login_as_employee(@vertical)
    get achievement_approvals_path(stage: "vertical")

    assert_response :success
    assert_includes response.body, "MIS Achievement Project"
    assert_includes response.body, "Corrected by MIS"
  end

  test "mis can filter achievement entry by project before choosing fco" do
    other_row = ActionPlanRow.create!(
      po_id: "PO-OTHER",
      project_name: "Other MIS Project",
      user_id: "77",
      user_name: "Other FCO",
      to_id: "TO-OTHER",
      to_name: "Other TO",
      statte: "MP",
      asa_theme_id: "1",
      asa_theme: "Livelihood",
      asa_activity_id: "1.9",
      asa_activity_name: "Other activity",
      activity: "Other work",
      unit_type: "Nos",
      apr: 2,
      apr_t: 1,
      planned_total: 2
    )

    login_as_admin

    get achievement_entry_path(project: @row.project_name)

    assert_response :success
    assert_select "select[name=project] option[value=?][selected]", @row.project_name
    assert_select "select[name=fco_id] option[value='9']"
    assert_select "select[name=fco_id] option", text: "Other FCO", count: 0

    get achievement_entry_path(project: @row.project_name, fco_id: "9", to_id: @row.to_id, month: "apr")

    assert_response :success
    assert_select "input[name=?]:not([disabled])", "achievements[#{@row.id}]"
    assert_select "input[name=?]", "achievements[#{other_row.id}]", count: 0
  end

  test "mis edit after vertical approval replaces old pending queue item with a fresh vertical approval" do
    pending_po_submission = create_submission!(
      status: "pending",
      current_stage: "po",
      vertical_reviewed_at: 1.day.ago,
      vertical_remark: "Forwarded"
    )
    pending_po_submission.achievement_submission_rows.create!(
      action_plan_row: @row,
      month: "apr",
      target_value: 5,
      achievement_value: 3
    )

    login_as_admin

    assert_difference -> { AchievementSubmission.count }, 1 do
      patch achievement_entry_path,
        params: edit_params(achievement: 6, remark: "PO queue correction", commit: "Save Draft")
    end

    assert_redirected_to achievement_entry_path(fco_id: "9", to_id: @row.to_id, project: @row.project_name, month: "apr")
    assert_equal 6, @row.reload.apr_t
    assert pending_po_submission.reload.superseded?
    assert_equal 0, AchievementSubmission.pending_for_stage("po").count

    reapproval = AchievementSubmission.where(status: "pending", current_stage: "vertical").order(:submitted_at, :id).last
    assert_equal @vertical.id, reapproval.vertical_approver_id
    assert_equal [ @row.id ], reapproval.achievement_submission_rows.pluck(:action_plan_row_id)
    assert_equal [ 6 ], reapproval.achievement_submission_rows.pluck(:achievement_value)
  end

  test "mis can upload edited achievement excel without clearing untouched old data" do
    untouched_row = ActionPlanRow.create!(
      po_id: "PO-MIS-ID",
      project_name: @row.project_name,
      user_id: "9",
      user_name: "MIS Edit FCO",
      to_id: @row.to_id,
      to_name: @row.to_name,
      statte: "MP",
      asa_theme_id: "1",
      asa_theme: "Livelihood",
      asa_activity_id: "1.2",
      asa_activity_name: "Follow-up visit",
      activity: "Visit completed",
      unit_type: "Nos",
      apr: 4,
      apr_t: 2,
      planned_total: 4
    )
    AchievementEntryDetail.create!(action_plan_row: untouched_row, month: "apr", remark: "Keep existing remark")
    approved_submission = create_submission!(
      status: "approved",
      current_stage: "complete",
      vertical_reviewed_at: 3.days.ago,
      po_reviewed_at: 2.days.ago,
      coo_reviewed_at: 1.day.ago
    )
    approved_submission.achievement_submission_rows.create!(
      action_plan_row: @row,
      month: "apr",
      target_value: 5,
      achievement_value: 3
    )

    login_as_admin
    upload = edited_achievement_upload([
      [ @row.id, @row.project_name, 8, "Excel correction" ],
      [ 999_999, "Wrong project", 99, "Should not be applied" ]
    ])

    assert_no_difference -> { ActionPlanRow.count } do
      assert_difference -> { AchievementSubmission.count }, 1 do
        post import_excel_achievement_entry_path,
          params: selection_params.merge(achievement_excel_file: upload)
      end
    end

    assert_redirected_to achievement_entry_path(fco_id: "9", to_id: @row.to_id, project: @row.project_name, month: "apr")
    assert_equal 8, @row.reload.apr_t
    assert_equal "Excel correction", AchievementEntryDetail.find_by!(action_plan_row: @row, month: "apr").remark
    assert_equal 2, untouched_row.reload.apr_t
    assert_equal "Keep existing remark", AchievementEntryDetail.find_by!(action_plan_row: untouched_row, month: "apr").remark
    assert approved_submission.reload.approved?

    reapproval = AchievementSubmission.where(status: "pending", current_stage: "vertical").order(:submitted_at, :id).last
    assert_equal [ @row.id ], reapproval.achievement_submission_rows.pluck(:action_plan_row_id)
    assert_equal [ 8 ], reapproval.achievement_submission_rows.pluck(:achievement_value)
  ensure
    upload&.close
    File.unlink(upload.path) if upload&.path.present? && File.exist?(upload.path)
  end

  private

  def create_submission!(attributes)
    AchievementSubmission.create!(
      {
        employee: @fco,
        fco_id: @row.user_id,
        fco_name: @row.user_name,
        to_id: @row.to_id,
        to_name: @row.to_name,
        project_name: @row.project_name,
        po_id: @row.po_id,
        state_code: @row.statte,
        asa_theme_id: @row.asa_theme_id,
        month: "apr",
        submission_remark: "Submitted",
        vertical_approver: @vertical,
        po_approver: @po,
        coo_approver: @coo,
        submitted_at: 4.days.ago
      }.merge(attributes)
    )
  end

  def edit_params(achievement:, remark:, commit:)
    selection_params.merge(
      achievements: { @row.id.to_s => achievement.to_s },
      remarks: { @row.id.to_s => remark },
      submission_remark: "MIS corrected entry",
      commit: commit
    )
  end

  def selection_params
    {
      fco_id: "9",
      to_id: @row.to_id,
      project: @row.project_name,
      month: "apr"
    }
  end

  def edited_achievement_upload(rows)
    file = Tempfile.new([ "achievement-entry-edit", ".csv" ])
    file.write(CSV.generate do |csv|
      csv << [ "Row ID", "Project", "Apr Achievement", "Remark" ]
      rows.each { |row| csv << row }
    end)
    file.close

    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end

  def login_as_admin
    post login_path, params: { login: @admin.login, password: "secret" }
  end

  def login_as_employee(employee)
    post login_path, params: { login: employee.employee_code, password: "secret" }
  end
end

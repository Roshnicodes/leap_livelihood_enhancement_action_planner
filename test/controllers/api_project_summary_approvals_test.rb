require "test_helper"

class ApiProjectSummaryApprovalsTest < ActionDispatch::IntegrationTest
  setup do
    @first_approver = Employee.create!(
      employee_code: ProjectSummarySubmission::FIRST_APPROVER_EMPLOYEE_CODE,
      name: "COO Approver",
      active: true
    )
    @final_approver = Employee.create!(
      employee_code: ProjectSummarySubmission::FINAL_APPROVER_EMPLOYEE_CODE,
      name: "Director Approver",
      active: true
    )
    @submitter = Employee.create!(employee_code: "1006", name: "Summary Submitter", active: true)
    User.create!(login: @first_approver.employee_code, employee: @first_approver, password: "secret")
    User.create!(login: @final_approver.employee_code, employee: @final_approver, password: "secret")
    VerticalPercent.create!(vertical_name: "Approval Vertical", total: 100, apr: 100)
    ProjectInformationSheet.create!(project_id: "PID-101", project_title: "Approval Project")
    @active_activity = matching_activity!(
      allocated_fund: 100,
      remaining_fund: 100,
      active: true,
      import_flag: 0
    )
    @disabled_activity = matching_activity!(
      allocated_fund: 777,
      remaining_fund: 777,
      active: false,
      import_flag: 0
    )
    @archived_activity = matching_activity!(
      allocated_fund: 999,
      remaining_fund: 999,
      active: true,
      import_flag: 1
    )
    @submission = ProjectSummarySubmission.create!(
      employee: @submitter,
      approver: @first_approver,
      submission_remark: "Please approve",
      total_amount: 120,
      submitted_at: Time.current
    )
    @submission.project_summary_submission_items.create!(
      project_name: "Approval Project",
      activity_name: "Approval Activity",
      vertical_name: "Approval Vertical",
      total_amount: 120,
      changed_total: 120,
      apr: 120
    )
    @source_file_path = Rails.root.join("tmp", "api_pb_source_#{SecureRandom.hex(8)}.csv")
    FileUtils.mkdir_p(@source_file_path.dirname)
    File.write(
      @source_file_path,
      [
        "Project Name,Activity,Vertical,BLI Allocated Fund,BLI Remaining Fund",
        "Approval Project,Approval Activity,Approval Vertical,100,100"
      ].join("\n")
    )
    PbImportFile.create!(
      original_filename: @source_file_path.basename.to_s,
      content_type: "text/csv",
      byte_size: File.size(@source_file_path),
      storage_path: @source_file_path.relative_path_from(Rails.root).to_s,
      status: "imported",
      file_kind: "source",
      financial_year: PbImportFile.financial_year_for,
      imported_at: Time.current
    )
  end

  teardown do
    File.delete(@source_file_path) if @source_file_path && File.exist?(@source_file_path)
  end

  test "project summary approval api returns pending pnb rows" do
    login_as(@first_approver)

    get "/api/project_summary_approvals", params: { vertical: "Approval Vertical" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Approval Vertical", payload["filters"]["vertical"]
    assert_equal 1, payload["summary"]["submission_count"]
    assert_equal "120.00", payload["summary"]["total_amount"]
    assert_equal "first_approval", payload["submissions"].first["stage"]
    assert_equal true, payload["submissions"].first["can_act"]
    project_group = payload["project_record_groups"].first
    item = payload["submissions"].first["items"].first
    assert_equal "PID-101", project_group["project_id"]
    assert_equal "PID-101", item["project_id"]
    assert_equal "Colored BLI Name", item["project_bli_name"]
    assert_equal "BLI-APPROVAL", item["project_bli_code"]
    assert_equal "BLI-APPROVAL", item["bli_code"]
    assert_equal "100.00", item["project_bli_allocated_fund"]
    assert_equal "Summary Submitter", item["responsible_user_name"]
    assert_equal "Approval Activity", item["asa_activity_name"]
    assert_equal "120.00", item["month_amounts"]["apr"]
    assert_equal "Colored BLI Name", item["colored_source_data"]["project_bli_name"]
  end

  test "project summary approval api approves without touching old pb rows" do
    login_as(@first_approver)

    patch "/api/project_summary_approvals/#{@submission.id}/approve",
      params: { approval_remark: "Forwarded" }

    assert_response :success
    first_payload = JSON.parse(response.body)
    assert_equal "forwarded", first_payload["action"]
    assert_equal "final_approval", first_payload["submission"]["stage"]
    assert_equal @final_approver.id, @submission.reload.approver_id
    assert_equal @first_approver.id, @submission.first_approver_id

    delete logout_path
    login_as(@final_approver)

    patch "/api/project_summary_approvals/#{@submission.id}/approve",
      params: { approval_remark: "Approved" }

    assert_response :success
    final_payload = JSON.parse(response.body)
    assert_equal "approved", final_payload["action"]
    assert @submission.reload.approved?
    assert_equal BigDecimal("120"), @active_activity.reload.allocated_fund
    assert_equal BigDecimal("120"), @active_activity.remaining_fund
    assert_equal BigDecimal("777"), @disabled_activity.reload.allocated_fund
    assert_equal BigDecimal("999"), @archived_activity.reload.allocated_fund
  end

  test "project summary return api requires remark" do
    login_as(@first_approver)

    patch "/api/project_summary_approvals/#{@submission.id}/return", params: { approval_remark: "" }

    assert_response :unprocessable_entity
    assert_equal "Return remark is required.", JSON.parse(response.body)["error"]
    assert @submission.reload.pending?
  end

  private

  def login_as(employee)
    post login_path, params: { login: employee.employee_code, password: "secret" }
  end

  def matching_activity!(attributes)
    BliActivity.create!(
      employee: @submitter,
      project_name: "Approval Project",
      vertical_name: "Approval Vertical",
      activity_name: "Approval Activity",
      responsible_user_name: @submitter.name,
      bli_code: "BLI-APPROVAL",
      name: "Colored BLI Name",
      **attributes
    )
  end
end

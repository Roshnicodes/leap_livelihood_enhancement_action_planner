require "test_helper"

class ApprovalMailNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous_url = ENV["LEAP_MAIL_RELAY_URL"]
    ENV["LEAP_MAIL_RELAY_URL"] = "https://krai.example.test/"
    @fco = Employee.create!(employee_code: "MAIL-FCO", name: "Mail FCO", email: "fco@example.test")
    @po = Employee.create!(employee_code: "MAIL-PO", name: "Mail PO", email: "po@example.test")
    @coo = Employee.find_by(employee_code: ActionPlanSubmission::COO_EMPLOYEE_CODE) ||
      Employee.create!(employee_code: ActionPlanSubmission::COO_EMPLOYEE_CODE, name: "Mail COO")
    @coo.update!(email: "coo@example.test")
    @ownership = ProjectOwnership.create!(po_id: "PO-MAIL", project_name: "Mail Project", project_owner_id: @po.employee_code)
  end

  teardown do
    ENV["LEAP_MAIL_RELAY_URL"] = @previous_url
    clear_enqueued_jobs
  end

  test "action plan mails the approver on submit, both sides on each approval and the submitter on return" do
    submission = ActionPlanSubmission.create!(
      employee: @fco, project_ownership: @ownership, po_id: "PO-MAIL", project_name: "Mail Project",
      status: "pending", current_stage: "po", submitted_at: Time.current
    )
    assert_equal [ [ "action_plan_pending", "po@example.test" ] ], sent_mails
    assert_includes sent_params.first["link"], "/action_plan_approvals/po"

    clear_enqueued_jobs
    submission.update!(current_stage: "coo", po_reviewed_at: Time.current, po_remark: "Looks fine")
    assert_equal [ [ "action_plan_level_approved", "fco@example.test" ], [ "action_plan_pending", "coo@example.test" ] ], sent_mails
    assert_includes sent_params.first["message"], "Project Owner (Mail PO)"
    assert_includes sent_params.first["message"], "Looks fine"

    clear_enqueued_jobs
    submission.update!(status: "returned", coo_reviewed_at: Time.current, coo_remark: "Fix June targets")
    assert_equal [ [ "action_plan_returned", "fco@example.test" ] ], sent_mails
    assert_includes sent_params.first["message"], "Fix June targets"

    clear_enqueued_jobs
    submission.update!(status: "pending", current_stage: "po", submitted_at: 1.minute.from_now)
    assert_equal [ [ "action_plan_pending", "po@example.test" ] ], sent_mails

    clear_enqueued_jobs
    submission.update!(current_stage: "coo", po_reviewed_at: Time.current)
    clear_enqueued_jobs
    submission.update!(status: "approved", current_stage: "complete", coo_reviewed_at: Time.current)
    assert_equal [ [ "action_plan_approved", "fco@example.test" ] ], sent_mails
    assert_includes sent_params.first["message"], "COO"
  end

  test "project summary mails the first approver, then the final approver, then the submitter" do
    first = Employee.find_by(employee_code: ProjectSummarySubmission::FIRST_APPROVER_EMPLOYEE_CODE) || @coo
    first.update!(email: "first@example.test")
    final = Employee.find_by(employee_code: ProjectSummarySubmission::FINAL_APPROVER_EMPLOYEE_CODE) ||
      Employee.create!(employee_code: ProjectSummarySubmission::FINAL_APPROVER_EMPLOYEE_CODE, name: "Mail Director")
    final.update!(email: "final@example.test")

    submission = ProjectSummarySubmission.create!(employee: @fco, status: "pending", total_amount: 100, submitted_at: Time.current)
    assert_equal [ [ "project_summary_pending", "first@example.test" ] ], sent_mails

    clear_enqueued_jobs
    submission.update!(approver: final, first_approver: first, first_approved_at: Time.current)
    assert_equal [ [ "project_summary_level_approved", "fco@example.test" ], [ "project_summary_pending", "final@example.test" ] ], sent_mails

    clear_enqueued_jobs
    submission.update!(status: "approved", reviewed_at: Time.current)
    assert_equal [ [ "project_summary_approved", "fco@example.test" ] ], sent_mails
  end

  test "sends nothing until the relay is configured" do
    ENV["LEAP_MAIL_RELAY_URL"] = nil

    ActionPlanSubmission.create!(
      employee: @fco, project_ownership: @ownership, po_id: "PO-MAIL", project_name: "Mail Project",
      status: "pending", current_stage: "po", submitted_at: Time.current
    )

    assert_empty sent_mails
  end

  test "skips approvers without an email" do
    @po.update!(email: nil)

    ActionPlanSubmission.create!(
      employee: @fco, project_ownership: @ownership, po_id: "PO-MAIL", project_name: "Mail Project",
      status: "pending", current_stage: "po", submitted_at: Time.current
    )

    assert_empty sent_mails
  end

  test "relay builds krai's GET request from the mail fields" do
    uri = LeapMailRelay.request_uri(
      "to_email" => "po@example.test", "to_name" => "Mail PO", "subject" => "Approval pending",
      "message" => "Please review", "link" => "https://leap.example.test/x"
    )

    assert_equal "https://krai.example.test/leap_nnotify.aspx", "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal "po@example.test", URI.decode_www_form(uri.query).to_h["to_email"]
  end

  private

  def sent_params
    enqueued_jobs.select { |job| job["job_class"] == "LeapMailJob" }.map { |job| job["arguments"].last.except("_aj_ruby2_keywords", "_aj_symbol_keys") }
  end

  def sent_mails
    enqueued_jobs.select { |job| job["job_class"] == "LeapMailJob" }.map { |job| [ job["arguments"].first, job["arguments"].last["to_email"] ] }
  end
end

class ProjectSummaryApprovalRecordsController < ApplicationController
  include ProjectSummaryReviewPresenter

  before_action :require_login
  before_action :require_summary_access

  RECORD_STATUS_OPTIONS = [
    [ "All Status", "" ],
    [ "Forwarded", "forwarded" ],
    [ "Approved", "approved" ],
    [ "Returned", "returned" ]
  ].freeze

  def index
    ProjectSummarySubmissionItem.reset_column_information

    @status_options = RECORD_STATUS_OPTIONS
    @selected_status = params[:status].to_s.presence_in(RECORD_STATUS_OPTIONS.map(&:last).compact_blank)
    @submissions = approval_records_scope
      .includes(:employee, :approver, :first_approver, :project_summary_submission_items)
      .order(submitted_at: :desc)
    @submissions = filter_submissions_by_record_status(@submissions, @selected_status) if @selected_status.present?
    @vertical_options = vertical_options_for(@submissions)
    @selected_vertical = params[:vertical].to_s.presence_in(@vertical_options)
    @filtered_submissions = @selected_vertical.present? ? filter_submissions_by_vertical(@submissions, @selected_vertical) : @submissions
    @record_entries = approval_record_entries_for(@filtered_submissions)
    @total_records = @submissions.size
    @filtered_count = @record_entries.size
  end

  private

  def require_summary_access
    return if current_user.admin? || summary_approver? || summary_viewer?

    redirect_to dashboard_path, alert: "Approval access required."
  end

  def summary_approver?
    ProjectSummarySubmission.summary_approver?(current_user.employee)
  end

  def summary_viewer?
    ProjectSummarySubmission.summary_viewer?(current_user.employee)
  end

  def first_stage_approver?
    current_user.employee&.id == ProjectSummarySubmission.first_approver_employee&.id
  end

  def final_stage_approver?
    current_user.employee&.id == ProjectSummarySubmission.final_approver_employee&.id
  end

  def approval_records_scope
    if current_user.admin? || summary_viewer?
      ProjectSummarySubmission.where(status: %w[approved returned])
        .or(ProjectSummarySubmission.where(status: "pending").where.not(first_approver_id: nil))
    elsif first_stage_approver?
      employee = current_user.employee
      ProjectSummarySubmission.where(first_approver: employee)
        .or(ProjectSummarySubmission.where(approver: employee, status: "returned"))
    elsif final_stage_approver?
      ProjectSummarySubmission.where(approver: current_user.employee, status: %w[approved returned])
    else
      ProjectSummarySubmission.none
    end
  end
end

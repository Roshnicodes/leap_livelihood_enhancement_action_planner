class ProjectSummaryApprovalsController < ApplicationController
  include ProjectSummaryReviewPresenter

  before_action :require_login
  before_action :require_summary_access
  before_action :require_summary_approver, only: %i[approve return_summary bulk_approve bulk_return]
  before_action :set_submission, only: %i[approve return_summary]

  def index
    ProjectSummarySubmissionItem.reset_column_information

    @base_submissions = approval_scope
      .includes(:employee, :project_summary_submission_items)
      .order(submitted_at: :desc)
    @submissions = @base_submissions
    @vertical_options = vertical_options_for(@submissions)
    @selected_vertical = params[:vertical].to_s.presence_in(@vertical_options) || @vertical_options.first
    @vertical_submissions = @selected_vertical.present? ? filter_submissions_by_vertical(@submissions, @selected_vertical) : []
    @pending_submissions = @vertical_submissions.select(&:pending?)
    @summary_submissions = @pending_submissions.presence || @vertical_submissions
    @summary_rows = summary_rows_for(@summary_submissions)
    @summary_rows = filter_summary_rows_by_vertical(@summary_rows, @selected_vertical) if @selected_vertical.present?
    @project_record_groups = project_record_groups_for(@summary_rows)
    @activity_summaries = activity_summaries_for(@summary_rows)
    @overall_total = @summary_rows.sum { |row| row[:total_amount].to_d }
    @overall_month_totals = month_totals_for(@summary_rows)
    @overall_month_changes = month_changes_for(@summary_rows)
    @summary_project_count = @summary_rows.map { |row| row[:project_name] }.compact_blank.uniq.size
    @summary_departments = @summary_submissions.map { |submission| submission.employee.department.presence || "Unassigned Department" }.uniq.sort
    @summary_submission_remarks = @summary_submissions.map(&:submission_remark).compact_blank.uniq
    @pending_group_count = pending_vertical_count_for(@base_submissions)
  end

  def approve
    update_submission!("approved")
    redirect_to project_summary_approvals_path(filter_params), notice: "Project summary approved successfully."
  end

  def return_summary
    if params[:approval_remark].to_s.strip.blank?
      redirect_to project_summary_approvals_path(filter_params), alert: "Return remark is required."
      return
    end

    update_submission!("returned")
    redirect_to project_summary_approvals_path(filter_params), notice: "Project summary returned successfully."
  end

  def bulk_approve
    update_submissions!("approved")
    redirect_to project_summary_approvals_path(filter_params), notice: "Project summaries approved successfully."
  end

  def bulk_return
    if params[:approval_remark].to_s.strip.blank?
      redirect_to project_summary_approvals_path(filter_params), alert: "Return remark is required."
      return
    end

    update_submissions!("returned")
    redirect_to project_summary_approvals_path(filter_params), notice: "Project summaries returned successfully."
  end

  private

  def require_summary_access
    return if current_user.admin? || summary_approver? || summary_viewer?

    redirect_to dashboard_path, alert: "Approval access required."
  end

  def require_summary_approver
    return if current_user.admin? || current_stage_approver?

    redirect_to dashboard_path, alert: "Approval access required."
  end

  def filter_params
    params.permit(:vertical).to_h.compact_blank
  end

  def set_submission
    @submission = approval_scope.find(params[:id])
  end

  def update_submission!(status)
    @submission.update!(approval_attributes_for(@submission, status))
  end

  def update_submissions!(status)
    submissions = approval_scope.where(status: "pending", id: params.fetch(:submission_ids, []))
    reviewed_at = Time.current

    ProjectSummarySubmission.transaction do
      submissions.find_each do |submission|
        submission.update!(approval_attributes_for(submission, status, reviewed_at))
      end
    end
  end

  def approval_scope
    if current_user.admin? || summary_viewer?
      ProjectSummarySubmission.all
    else
      ProjectSummarySubmission.where(approver: current_user.employee)
    end
  end

  def summary_approver?
    ProjectSummarySubmission.summary_approver?(current_user.employee)
  end

  def summary_viewer?
    ProjectSummarySubmission.summary_viewer?(current_user.employee)
  end

  def current_stage_approver?
    return false unless summary_approver?

    approval_scope.where(status: "pending", approver: current_user.employee).exists?
  end

  def approval_attributes_for(submission, status, reviewed_at = Time.current)
    return return_attributes(status, reviewed_at) if status == "returned"

    final_approver = ProjectSummarySubmission.final_approver_employee
    if submission.approver_id != final_approver&.id
      {
        status: "pending",
        approver: final_approver,
        first_approver: submission.first_approver || current_user&.employee || submission.approver,
        approval_remark: params[:approval_remark].to_s.strip,
        reviewed_at: nil
      }
    else
      {
        status: "approved",
        approval_remark: params[:approval_remark].to_s.strip,
        reviewed_at: reviewed_at
      }
    end
  end

  def return_attributes(status, reviewed_at)
    {
      status: status,
      approval_remark: params[:approval_remark].to_s.strip,
      reviewed_at: reviewed_at
    }
  end

  def pending_vertical_count_for(submissions)
    submissions
      .select(&:pending?)
      .flat_map do |submission|
        submission.project_summary_submission_items.map { |item| item.vertical_name.presence || "Unassigned Vertical" }
      end
      .uniq
      .size
  end
end

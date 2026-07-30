class ProjectSummaryApprovalsController < ApplicationController
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
    @selected_vertical = params[:vertical].to_s.presence_in(@vertical_options)
    @vertical_submissions = @selected_vertical.present? ? filter_submissions_by_vertical(@submissions, @selected_vertical) : []
    @pending_submissions = @vertical_submissions.select(&:pending?)
    @summary_submissions = @pending_submissions.presence || @vertical_submissions
    @summary_rows = summary_rows_for(@summary_submissions)
    @summary_rows = filter_summary_rows_by_vertical(@summary_rows, @selected_vertical) if @selected_vertical.present?
    @activity_summaries = activity_summaries_for(@summary_rows)
    @vertical_summaries = vertical_summaries_for(@summary_rows)
    @overall_total = @summary_rows.sum { |row| row[:total_amount].to_d }
    @overall_month_totals = month_totals_for(@summary_rows)
    @overall_month_changes = month_changes_for(@summary_rows)
    @summary_project_count = @summary_rows.map { |row| row[:project_name] }.compact_blank.uniq.size
    @summary_departments = @summary_submissions.map { |submission| submission.employee.department.presence || "Unassigned Department" }.uniq.sort
    @summary_submission_remarks = @summary_submissions.map(&:submission_remark).compact_blank.uniq
    @pending_group_count = @pending_submissions.size
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
    return if current_user.admin? || summary_approver?

    redirect_to dashboard_path, alert: "Approval access required."
  end

  def filter_params
    params.permit(:vertical).to_h.compact_blank
  end

  def set_submission
    @submission = approval_scope.find(params[:id])
  end

  def update_submission!(status)
    @submission.update!(
      status: status,
      approval_remark: params[:approval_remark].to_s.strip,
      reviewed_at: Time.current
    )
  end

  def update_submissions!(status)
    submissions = approval_scope.where(status: "pending", id: params.fetch(:submission_ids, []))
    reviewed_at = Time.current

    ProjectSummarySubmission.transaction do
      submissions.find_each do |submission|
        submission.update!(
          status: status,
          approval_remark: params[:approval_remark].to_s.strip,
          reviewed_at: reviewed_at
        )
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

  def vertical_options_for(submissions)
    submissions
      .flat_map do |submission|
        submission.project_summary_submission_items.map { |item| item.vertical_name.presence || "Unassigned Vertical" }
      end
      .uniq
      .sort
  end

  def filter_submissions_by_vertical(submissions, vertical_name)
    submissions.select do |submission|
      submission.project_summary_submission_items.any? do |item|
        (item.vertical_name.presence || "Unassigned Vertical") == vertical_name
      end
    end
  end

  def filter_summary_rows_by_vertical(rows, vertical_name)
    rows.select { |row| (row[:vertical_name].presence || "Unassigned Vertical") == vertical_name }
  end

  def summary_approver?
    ProjectSummarySubmission.summary_approver?(current_user.employee)
  end

  def summary_viewer?
    ProjectSummarySubmission.summary_viewer?(current_user.employee)
  end

  def summary_rows_for(submissions)
    submissions.flat_map(&:project_summary_submission_items).map do |item|
      month_amounts = VerticalPercent::MONTH_COLUMNS.index_with { |month| item.public_send(month) }
      planned_month_amounts = planned_month_amounts_for(item.total_amount, item.vertical_name)

      {
        project_name: item.project_name,
        activity_name: item.activity_name,
        vertical_name: item.vertical_name,
        total_amount: item.total_amount,
        month_amounts: month_amounts,
        planned_month_amounts: planned_month_amounts,
        month_deltas: month_deltas_for(month_amounts, planned_month_amounts)
      }
    end
  end

  def activity_summaries_for(rows)
    rows
      .group_by { |row| row[:activity_name].presence || "Unassigned Activity" }
      .map do |activity_name, activity_rows|
        projects = project_breakdown_for(activity_rows)

        {
          activity_name: activity_name,
          project_count: projects.size,
          total_amount: activity_rows.sum { |row| row[:total_amount].to_d },
          month_totals: month_totals_for(activity_rows),
          month_changes: month_changes_for(activity_rows),
          projects: projects
        }
      end
      .sort_by { |activity| [ -activity[:total_amount], activity[:activity_name].to_s ] }
  end

  def vertical_summaries_for(rows)
    rows
      .group_by { |row| row[:vertical_name].presence || "Unassigned Vertical" }
      .map do |vertical_name, vertical_rows|
        projects = project_breakdown_for(vertical_rows)
        changed_month_count = vertical_rows.sum do |row|
          row[:month_deltas].values.count { |delta| delta.to_d.abs >= 0.01 }
        end

        {
          vertical_name: vertical_name,
          project_count: projects.size,
          row_count: vertical_rows.size,
          total_amount: vertical_rows.sum { |row| row[:total_amount].to_d },
          changed_month_count: changed_month_count,
          projects: projects
        }
      end
      .sort_by { |vertical| [ -vertical[:total_amount], vertical[:vertical_name].to_s ] }
  end

  def project_breakdown_for(rows)
    rows
      .group_by { |row| row[:project_name].presence || "Unassigned Project" }
      .map do |project_name, project_rows|
        {
          project_name: project_name,
          total_amount: project_rows.sum { |row| row[:total_amount].to_d }
        }
      end
      .sort_by { |project| [ -project[:total_amount], project[:project_name].to_s ] }
  end

  def month_totals_for(rows)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      rows.sum { |row| row[:month_amounts][month].to_d }
    end
  end

  def month_changes_for(rows)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      rows.filter_map do |row|
        delta = row[:month_deltas][month].to_d
        delta if delta.abs >= 0.01
      end
    end
  end

  def planned_month_amounts_for(total_amount, vertical_name)
    month_amounts_for(total_amount, VerticalPercent.find_by(vertical_name: vertical_name))
  end

  def month_deltas_for(month_amounts, planned_month_amounts)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      month_amounts[month].to_d - planned_month_amounts[month].to_d
    end
  end

  def month_amounts_for(total_amount, percent)
    amounts = {}
    running_total = BigDecimal("0")

    VerticalPercent::MONTH_COLUMNS.each_with_index do |month, index|
      monthly_percent = percent&.public_send(month) || 0
      amount = if index == VerticalPercent::MONTH_COLUMNS.size - 1
        total_amount - running_total
      else
        (total_amount * monthly_percent / 100).round(2)
      end

      amounts[month] = amount
      running_total += amount
    end

    amounts
  end
end

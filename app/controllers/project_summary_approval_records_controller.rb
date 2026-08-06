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
  RECORD_TYPE_OPTIONS = [ [ "P&B", "pnb" ], [ "Action Plan", "action_plan" ] ].freeze

  def index
    ProjectSummarySubmissionItem.reset_column_information

    @status_options = RECORD_STATUS_OPTIONS
    @record_type_options = RECORD_TYPE_OPTIONS
    @selected_record_type = params[:record_type].to_s.presence_in(RECORD_TYPE_OPTIONS.map(&:last)) || "pnb"
    @selected_status = params[:status].to_s.presence_in(RECORD_STATUS_OPTIONS.map(&:last).compact_blank)
    pnb_scope = approval_records_scope
      .includes(:employee, :approver, :first_approver, :project_summary_submission_items)
      .order(submitted_at: :desc)
    @pnb_submissions = pnb_scope
    @pnb_submissions = filter_submissions_by_record_status(@pnb_submissions, @selected_status) if @selected_status.present?
    action_plan_scope = action_plan_records_scope
      .includes(:employee, :project_ownership, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
    @action_plan_submissions = action_plan_scope
    @action_plan_submissions = filter_action_plan_submissions_by_record_status(@action_plan_submissions, @selected_status) if @selected_status.present?

    pnb_records = approval_record_summaries_for(@pnb_submissions)
    @pnb_record_count = pnb_records.size
    @pnb_pending_count = pnb_records.count { |record| record[:status] == "pending" }
    @action_plan_record_count = @action_plan_submissions.size
    @action_plan_pending_count = @action_plan_submissions.count(&:pending?)
    @vertical_options = vertical_options_for(@pnb_submissions)
    @selected_vertical = params[:vertical].to_s.presence_in(@vertical_options)
    @filtered_pnb_submissions = @selected_vertical.present? ? filter_submissions_by_vertical(@pnb_submissions, @selected_vertical) : @pnb_submissions
    @record_entries = selected_record_entries
    @total_records = @pnb_record_count + @action_plan_record_count
    @filtered_count = @record_entries.size
  end

  private

  def require_summary_access
    return if current_user.admin? || summary_approver? || action_plan_approver?

    redirect_to dashboard_path, alert: "Approval access required."
  end

  def summary_approver?
    ProjectSummarySubmission.summary_approver?(current_user.employee)
  end

  def action_plan_approver?
    %w[po coo director].any? { |stage| ActionPlanSubmission.stage_approver?(current_user.employee, stage) }
  end

  def first_stage_approver?
    current_user.employee&.id == ProjectSummarySubmission.first_approver_employee&.id
  end

  def final_stage_approver?
    current_user.employee&.id == ProjectSummarySubmission.final_approver_employee&.id
  end

  def approval_records_scope
    if current_user.admin?
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

  def action_plan_records_scope
    return ActionPlanSubmission.all if current_user.admin?

    employee = current_user.employee
    scopes = []
    scopes << ActionPlanSubmission.where(po_approver: employee) if ActionPlanSubmission.stage_approver?(employee, "po")
    scopes << ActionPlanSubmission.where(coo_approver: employee) if ActionPlanSubmission.stage_approver?(employee, "coo")
    scopes << ActionPlanSubmission.where(director_approver: employee) if ActionPlanSubmission.stage_approver?(employee, "director")
    return ActionPlanSubmission.none if scopes.blank?

    scopes.reduce { |combined, scope| combined.or(scope) }
  end

  def selected_record_entries
    entries = @selected_record_type == "action_plan" ? action_plan_record_entries : pnb_record_entries
    entries.sort_by { |entry| [ entry[:status_sort], entry[:submitted_at] || Time.at(0) ] }.reverse
  end

  def pnb_record_entries
    approval_record_summaries_for(@filtered_pnb_submissions).map do |record|
      {
        record_type: "P&B Summary",
        record_type_key: "pnb",
        scope_label: record[:vertical_name],
        submitted_by: record[:employee_name],
        total_amount: record[:total_amount],
        po_approval_label: "Not applicable",
        po_approval_badge: "not_submitted",
        coo_approval_label: record[:coo_approval_label],
        coo_approval_badge: record[:coo_approval_badge],
        director_approval_label: record[:director_approval_label],
        director_approval_badge: record[:director_approval_badge],
        remark: record[:remark],
        status: record[:status],
        status_sort: status_sort(record[:status]),
        submitted_at: record[:action_at]
      }
    end
  end

  def action_plan_record_entries
    @action_plan_submissions.map do |submission|
      rows = action_plan_record_rows(submission)
      {
        id: submission.id,
        record_type: submission.plan_type_label,
        record_type_key: "action_plan",
        scope_label: submission.project_name,
        submitted_by: submission.employee.name,
        total_amount: rows.sum { |row| row[:changed_total].to_i },
        row_count: rows.size,
        changed_month_count: rows.sum { |row| row[:month_deltas].values.count { |delta| delta.to_i != 0 } },
        rows: rows,
        po_approval_label: helpers.action_plan_stage_status(submission, "po")[:label],
        po_approval_badge: helpers.action_plan_stage_status(submission, "po")[:badge],
        coo_approval_label: helpers.action_plan_stage_status(submission, "coo")[:label],
        coo_approval_badge: helpers.action_plan_stage_status(submission, "coo")[:badge],
        director_approval_label: helpers.action_plan_stage_status(submission, "director")[:label],
        director_approval_badge: helpers.action_plan_stage_status(submission, "director")[:badge],
        remark: action_plan_record_remark(submission),
        status: submission.status,
        status_sort: status_sort(submission.status),
        submitted_at: submission.submitted_at
      }
    end
  end

  def action_plan_record_rows(submission)
    submission.scoped_action_plan_rows.to_a.map do |row|
      month_amounts = ActionPlanRow::MONTH_COLUMNS.index_with { |month| row.public_send(month).to_i }
      original_month_amounts = ActionPlanRow::MONTH_COLUMNS.index_with do |month|
        original_column = "original_#{month}"
        row.respond_to?(original_column) ? row.public_send(original_column).to_i : row.public_send(month).to_i
      end

      {
        project_name: row.project_name,
        asa_activity_id: row.asa_activity_id,
        asa_activity_name: row.asa_activity_name.presence || row.activity,
        theme: row.theme,
        unit_type: row.unit_type,
        planned_total: row.planned_total.to_i,
        changed_total: row.monthly_total,
        month_amounts: month_amounts,
        month_deltas: ActionPlanRow::MONTH_COLUMNS.index_with { |month| month_amounts[month] - original_month_amounts[month] }
      }
    end
  end

  def filter_action_plan_submissions_by_record_status(submissions, status_filter)
    case status_filter
    when "forwarded"
      submissions.select { |submission| submission.pending? && submission.current_stage != "po" }
    when "approved"
      submissions.select(&:approved?)
    when "returned"
      submissions.select(&:returned?)
    else
      submissions
    end
  end

  def action_plan_record_remark(submission)
    [
      submission.director_remark,
      submission.coo_remark,
      submission.po_remark,
      submission.submission_remark
    ].compact_blank.first
  end

  def status_sort(status)
    { "pending" => 3, "returned" => 2, "approved" => 1 }.fetch(status.to_s, 0)
  end
end

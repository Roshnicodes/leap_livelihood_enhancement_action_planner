require "csv"

class ActionPlanApprovalsController < ApplicationController
  before_action :require_login
  before_action :set_stage
  before_action :require_stage_access
  before_action :set_submission, only: %i[approve return_plan]

  helper_method :awaiting_this_stage?, :can_act_on_submission?, :submission_action_plan_summary, :submission_action_plan_rows

  def index
    @submissions = stage_history_scope
      .includes(:employee, :project_ownership, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
      .to_a
    @pending_submissions = @submissions.select { |submission| awaiting_this_stage?(submission) }

    respond_to do |format|
      format.html
      format.csv do
        send_data action_plan_approvals_csv,
          filename: "action_plan_#{@stage}_approvals_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(action_plan_approvals_csv, title: "Action Plan #{@stage.titleize} Approvals", sheet_name: "Approvals"),
          filename: "action_plan_#{@stage}_approvals_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  def approve
    @submission.update!(approval_attributes)
    ActionPlanMonthChange.mark_submission_rows!(@submission, status: "approved") if @submission.approved?
    redirect_to action_plan_approvals_path(stage: @stage), notice: "Action plan approved successfully."
  end

  def return_plan
    if params[:approval_remark].to_s.strip.blank?
      redirect_to action_plan_approvals_path(stage: @stage), alert: "Return remark is required."
      return
    end

    @submission.update!(return_attributes)
    redirect_to action_plan_approvals_path(stage: @stage), notice: "Action plan returned successfully."
  end

  private

  def set_stage
    @stage = params[:stage].to_s.presence_in(%w[po coo director]) || "po"
  end

  def require_stage_access
    return if current_user.admin?
    return if ActionPlanSubmission.stage_approver?(current_user.employee, @stage)

    redirect_to dashboard_path, alert: "Approval access required."
  end

  # Only plans sitting in this stage can be acted on.
  def approval_scope
    stage_history_scope.where(current_stage: @stage)
  end

  # Everything this approver is responsible for, including already-forwarded
  # plans, so each stage page doubles as a status history.
  def stage_history_scope
    return ActionPlanSubmission.all if current_user.admin?

    case @stage
    when "po"
      ActionPlanSubmission.where(po_approver: current_user.employee)
    when "coo"
      ActionPlanSubmission.where(coo_approver: current_user.employee)
    when "director"
      ActionPlanSubmission.where(director_approver: current_user.employee)
    end
  end

  def awaiting_this_stage?(submission)
    submission.pending? && submission.current_stage == @stage
  end

  def set_submission
    @submission = approval_scope.where(status: "pending").find(params[:id])
    return if can_act_on_submission?(@submission)

    redirect_to action_plan_approvals_path(stage: @stage), alert: "You can view this record, but approval is restricted to the assigned approver."
  end

  def approval_attributes
    reviewed_at = Time.current
    remark = params[:approval_remark].to_s.strip

    case @stage
    when "po"
      { current_stage: "coo", po_reviewed_at: reviewed_at, po_remark: remark }
    when "coo"
      { status: "approved", current_stage: "complete", coo_reviewed_at: reviewed_at, coo_remark: remark }
    else
      { status: "approved", current_stage: "complete", director_reviewed_at: reviewed_at, director_remark: remark }
    end
  end

  def return_attributes
    {
      status: "returned",
      "#{@stage}_reviewed_at": Time.current,
      "#{@stage}_remark": params[:approval_remark].to_s.strip
    }
  end

  def submission_action_plan_summary(submission)
    @submission_action_plan_summaries ||= {}
    @submission_action_plan_summaries[submission.id] ||= begin
      rows = submission.scoped_action_plan_rows
      month_pairs = ActionPlanRow::MONTH_DISPLAY_PAIRS
      row_list = rows.to_a

      {
        row_count: row_list.size,
        planned_total: rows.sum(:planned_total),
        target_total: row_list.sum(&:monthly_total),
        achievement_total: row_list.sum(&:target_total),
        changed_month_count: row_list.sum do |row|
          month_pairs.count do |pair|
            target_column = pair[:target_column]
            original_column = "original_#{target_column}"
            original_value = row.respond_to?(original_column) ? row.public_send(original_column).to_i : row.public_send(target_column).to_i

            row.public_send(target_column).to_i != original_value
          end
        end
      }
    end
  end

  def submission_action_plan_rows(submission)
    @submission_action_plan_rows ||= {}
    @submission_action_plan_rows[submission.id] ||= submission.scoped_action_plan_rows.to_a.map do |row|
      month_amounts = ActionPlanRow::MONTH_COLUMNS.index_with { |month| row.public_send(month).to_i }
      original_month_amounts = ActionPlanRow::MONTH_COLUMNS.index_with do |month|
        original_column = "original_#{month}"
        row.respond_to?(original_column) ? row.public_send(original_column).to_i : row.public_send(month).to_i
      end
      month_deltas = ActionPlanRow::MONTH_COLUMNS.index_with { |month| month_amounts[month] - original_month_amounts[month] }

      {
        project_name: row.project_name,
        asa_activity_id: row.asa_activity_id,
        asa_activity_name: row.asa_activity_name.presence || row.activity,
        theme: row.theme,
        unit_type: row.unit_type,
        planned_total: row.planned_total.to_i,
        changed_total: row.monthly_total,
        month_amounts: month_amounts,
        month_deltas: month_deltas
      }
    end
  end

  def can_act_on_submission?(submission)
    return false if @stage == "director"
    return false unless awaiting_this_stage?(submission)
    return false if current_user.admin?

    case @stage
    when "po"
      submission.po_approver_id == current_user.employee&.id
    when "coo"
      submission.coo_approver_id == current_user.employee&.id
    else
      false
    end
  end

  def action_plan_approvals_csv
    CSV.generate(headers: true) do |csv|
      csv << [ "Project", "Plan Type", "Project Owner", "Submitted By", "Submitted At", "No of Activity", "Total Target", "Month Changes", "Current Stage", "PO Approval", "COO Approval", "Director View", "Remark" ]

      @submissions.each do |submission|
        summary = submission_action_plan_summary(submission)
        csv << [
          submission.project_name,
          submission.plan_type_label,
          submission.project_ownership&.po_name.presence || helpers.action_plan_stage_actor(submission, "po"),
          [ submission.employee.employee_code, submission.employee.name ].compact_blank.join(" - "),
          helpers.format_record_datetime(submission.submitted_at),
          summary[:row_count],
          summary[:target_total],
          summary[:changed_month_count],
          submission.status_label,
          helpers.action_plan_stage_status(submission, "po")[:label],
          helpers.action_plan_stage_status(submission, "coo")[:label],
          helpers.action_plan_stage_status(submission, "director")[:label],
          submission.submission_remark
        ]
      end
    end
  end

end

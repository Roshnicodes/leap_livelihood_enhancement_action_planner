class AchievementApprovalsController < ApplicationController
  before_action :require_login
  before_action :set_stage
  before_action :require_stage_access
  before_action :set_submission, only: %i[approve return_submission]

  helper_method :awaiting_this_stage?, :can_act_on_submission?, :achievement_stage_status, :achievement_submission_rows

  def index
    @submissions = stage_history_scope
      .includes(:employee, :vertical_approver, :po_approver, :coo_approver, :director_approver, achievement_submission_rows: :action_plan_row)
      .order(submitted_at: :desc)
      .to_a
    @pending_submissions = @submissions.select { |submission| awaiting_this_stage?(submission) }
  end

  def approve
    @submission.update!(approval_attributes)
    redirect_to achievement_approvals_path(stage: @stage), notice: "Achievement request approved."
  end

  def return_submission
    if params[:approval_remark].to_s.strip.blank?
      redirect_to achievement_approvals_path(stage: @stage), alert: "Return remark is required."
      return
    end

    @submission.update!(return_attributes)
    redirect_to achievement_approvals_path(stage: @stage), notice: "Achievement request returned."
  end

  private

  def set_stage
    @stage = params[:stage].to_s.presence_in(%w[vertical po coo director]) || "vertical"
  end

  def require_stage_access
    return if current_user.admin?
    return if AchievementSubmission.stage_approver?(current_user.employee, @stage)

    fallback_stage = default_achievement_approval_stage
    if fallback_stage.present? && AchievementSubmission.stage_approver?(current_user.employee, fallback_stage)
      redirect_to achievement_approvals_path(stage: fallback_stage)
      return
    end

    redirect_to dashboard_path, alert: "Achievement approval access required."
  end

  def stage_history_scope
    return AchievementSubmission.all if current_user.admin?

    case @stage
    when "vertical"
      AchievementSubmission.where(vertical_approver: current_user.employee)
    when "po"
      AchievementSubmission.where(po_approver: current_user.employee)
    when "coo"
      AchievementSubmission.where(coo_approver: current_user.employee)
    when "director"
      AchievementSubmission.where(director_approver: current_user.employee)
    end
  end

  def approval_scope
    stage_history_scope.where(current_stage: @stage, status: "pending")
  end

  def awaiting_this_stage?(submission)
    submission.pending? && submission.current_stage == @stage
  end

  def set_submission
    @submission = approval_scope.find(params[:id])
    return if can_act_on_submission?(@submission)

    redirect_to achievement_approvals_path(stage: @stage), alert: "Approval is restricted to the assigned approver."
  end

  def can_act_on_submission?(submission)
    return false if @stage == "director"
    return false unless awaiting_this_stage?(submission)
    return false if current_user.admin?

    submission.public_send("#{@stage}_approver_id") == current_user.employee&.id
  end

  def approval_attributes
    reviewed_at = Time.current
    remark = params[:approval_remark].to_s.strip

    case @stage
    when "vertical"
      { current_stage: "po", vertical_reviewed_at: reviewed_at, vertical_remark: remark }
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

  def achievement_stage_status(submission, stage)
    reviewed_at = submission.public_send("#{stage}_reviewed_at")
    if reviewed_at.present?
      returned = submission.returned? && submission.current_stage == stage
      {
        label: "#{returned ? "Returned" : "Approved"} by #{submission.stage_actor(stage)} • #{helpers.format_record_datetime(reviewed_at)}",
        badge: returned ? "returned" : "approved"
      }
    elsif stage == "director"
      if submission.approved?
        { label: "View only • Final at COO", badge: "approved" }
      else
        { label: "View only", badge: "not_submitted" }
      end
    elsif submission.current_stage == stage
      { label: "Pending with #{submission.stage_actor(stage)}", badge: stage == "vertical" ? "pending" : "forwarded" }
    else
      { label: "Awaiting #{stage.to_s.titleize}", badge: "not_submitted" }
    end
  end

  def achievement_submission_rows(submission)
    items = submission.achievement_submission_rows.includes(:action_plan_row).sort_by do |item|
      row = item.action_plan_row
      [
        ActionPlanRow.format_decimal_string(row.asa_theme_id).to_f,
        ActionPlanRow.format_decimal_string(row.asa_activity_id).to_f,
        item.id
      ]
    end

    details = AchievementEntryDetail.for_rows(items.map(&:action_plan_row_id), submission.month)

    items.map do |item|
      row = item.action_plan_row
      detail = details[row.id]
      {
        row: row,
        target_value: row.public_send(submission.month).to_i,
        achievement_value: row.public_send("#{submission.month}_t").to_i,
        remark: detail&.remark,
        files: detail&.files
      }
    end
  end
end

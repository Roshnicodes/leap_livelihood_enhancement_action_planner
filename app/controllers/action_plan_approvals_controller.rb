class ActionPlanApprovalsController < ApplicationController
  before_action :require_login
  before_action :set_stage
  before_action :require_stage_access
  before_action :set_submission, only: %i[approve return_plan]

  def index
    @submissions = approval_scope
      .includes(:employee, :project_ownership, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
    @pending_submissions = @submissions.where(status: "pending")
  end

  def approve
    @submission.update!(approval_attributes)
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

  def approval_scope
    scope = ActionPlanSubmission.where(current_stage: @stage)
    return scope if current_user.admin?

    case @stage
    when "po"
      scope.where(po_approver: current_user.employee)
    when "coo"
      scope.where(coo_approver: current_user.employee)
    when "director"
      scope.where(director_approver: current_user.employee)
    end
  end

  def set_submission
    @submission = approval_scope.where(status: "pending").find(params[:id])
  end

  def approval_attributes
    reviewed_at = Time.current
    remark = params[:approval_remark].to_s.strip

    case @stage
    when "po"
      { current_stage: "coo", po_reviewed_at: reviewed_at, po_remark: remark }
    when "coo"
      { current_stage: "director", coo_reviewed_at: reviewed_at, coo_remark: remark }
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
end

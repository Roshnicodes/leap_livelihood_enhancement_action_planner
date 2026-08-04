class ApplicationController < ActionController::Base
  helper_method :current_user, :pending_project_summary_approval_count, :pending_action_plan_approval_count, :action_plan_stage_access?

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def require_login
    return if current_user&.admin? || current_user&.employee&.active?

    if current_user
      reset_session
      redirect_to login_path, alert: "Your employee login is inactive."
      return
    end

    redirect_to login_path, alert: "Please login to continue."
  end

  def require_admin
    return if current_user&.admin?

    redirect_to dashboard_path, alert: "Admin access required."
  end

  def pending_project_summary_approval_count
    return 0 unless current_user

    submissions = if current_user.admin?
      ProjectSummarySubmission.where(status: "pending")
    elsif ProjectSummarySubmission.summary_approver?(current_user.employee)
      ProjectSummarySubmission.where(status: "pending", approver: current_user.employee)
    else
      ProjectSummarySubmission.none
    end

    submissions
      .joins(:project_summary_submission_items)
      .distinct
      .pluck("project_summary_submission_items.vertical_name")
      .map { |vertical_name| vertical_name.presence || "Unassigned Vertical" }
      .uniq
      .size
  end

  def pending_action_plan_approval_count(stage)
    return 0 unless current_user
    return ActionPlanSubmission.pending_for_stage(stage).count if current_user.admin?

    ActionPlanSubmission.stage_pending_count(current_user.employee, stage)
  end

  def action_plan_stage_access?(stage)
    return false unless current_user
    return true if current_user.admin? && ActionPlanSubmission.pending_for_stage(stage).exists?

    ActionPlanSubmission.stage_approver?(current_user.employee, stage)
  end
end

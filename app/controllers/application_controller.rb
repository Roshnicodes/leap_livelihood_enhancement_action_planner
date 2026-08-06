class ApplicationController < ActionController::Base
  helper_method :current_user, :pending_project_summary_approval_count, :pending_action_plan_approval_count,
    :action_plan_stage_access?, :achievement_stage_access?, :pending_achievement_approval_count,
    :default_achievement_approval_stage

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

    redirect_to dashboard_path, alert: "PMC access required."
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
    return true if current_user.admin?

    ActionPlanSubmission.stage_approver?(current_user.employee, stage)
  end

  def pending_achievement_approval_count(stage)
    return 0 unless current_user
    return AchievementSubmission.pending_for_stage(stage).count if current_user.admin?

    AchievementSubmission.stage_pending_count(current_user.employee, stage)
  end

  def achievement_stage_access?(stage)
    return false unless current_user
    return true if current_user.admin?

    AchievementSubmission.stage_approver?(current_user.employee, stage)
  end

  # Sidebar / deep links should open a stage the user can actually open.
  # Prefer a stage that has pending work; otherwise first accessible stage.
  def default_achievement_approval_stage
    stages = %w[vertical po coo director]
    return "vertical" if current_user&.admin?

    accessible = stages.select { |stage| achievement_stage_access?(stage) }
    return "vertical" if accessible.empty?

    accessible.find { |stage| pending_achievement_approval_count(stage).positive? } || accessible.first
  end
end

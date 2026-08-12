class ApplicationController < ActionController::Base
  helper_method :current_user, :pending_project_summary_approval_count, :pending_action_plan_approval_count,
    :action_plan_stage_access?, :achievement_stage_access?, :pending_achievement_approval_count,
    :default_achievement_approval_stage,
    :menu_show_allocated_pb?, :menu_show_project_summary?, :menu_show_project_summary_record?,
    :menu_show_pb_summary_approval?, :menu_show_pb_approval_records?, :menu_show_budget_utilization?,
    :menu_show_budget_utilization_report?,
    :menu_show_project_action_plan?, :menu_show_achievement_entry?, :menu_show_achievement_approvals?,
    :menu_show_vertical_action_plan?, :menu_show_vertical_action_plan_record?,
    :menu_show_pis_report_upload?, :menu_show_donor_report_upload?, :menu_show_fund_report_upload?,
    :menu_show_action_plan_approval?, :menu_show_pb_section?, :menu_show_action_plan_section?

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

  def menu_employee
    current_user&.employee
  end

  def menu_show_allocated_pb?
    return true if current_user&.admin?
    return true if ProjectSummarySubmission.summary_access?(menu_employee)

    menu_employee&.bli_activities&.exists?
  end

  def menu_show_project_summary?
    return false if current_user&.admin?
    return false if ProjectSummarySubmission.summary_access?(menu_employee)

    menu_employee&.bli_activities&.exists?
  end

  def menu_show_project_summary_record?
    return true if current_user&.admin?
    return true if ProjectSummarySubmission.summary_access?(menu_employee)

    menu_employee&.bli_activities&.exists?
  end

  def menu_show_pb_summary_approval?
    current_user&.admin? || ProjectSummarySubmission.summary_access?(menu_employee)
  end

  def menu_show_pb_approval_records?
    current_user&.admin? || ProjectSummarySubmission.summary_access?(menu_employee)
  end

  def menu_show_budget_utilization?
    current_user.present?
  end

  def menu_show_budget_utilization_report?
    current_user.present?
  end

  def menu_show_project_action_plan?
    return true if current_user&.admin?
    return true if ProjectOwnership.for_employee(menu_employee).exists?
    return true if menu_employee&.action_plan_fco?

    false
  end

  def menu_show_achievement_entry?
    !current_user&.admin? && menu_employee&.action_plan_fco?
  end

  def menu_show_achievement_approvals?
    return true if current_user&.admin?

    %w[vertical po coo director].any? { |stage| achievement_stage_access?(stage) }
  end

  def menu_show_vertical_action_plan?
    return true if current_user&.admin?

    ActionPlanVerticalMapping.for_employee(menu_employee).exists?
  end

  def menu_show_vertical_action_plan_record?
    menu_show_vertical_action_plan?
  end

  def menu_show_pis_report_upload?
    current_user.present?
  end

  def menu_show_donor_report_upload?
    current_user.present?
  end

  def menu_show_fund_report_upload?
    current_user.present?
  end

  def menu_show_action_plan_approval?(stage)
    action_plan_stage_access?(stage)
  end

  def menu_show_pb_section?
    menu_show_allocated_pb? || menu_show_project_summary? || menu_show_project_summary_record? ||
      menu_show_pb_summary_approval? || menu_show_pb_approval_records? || menu_show_budget_utilization? ||
      menu_show_budget_utilization_report?
  end

  def menu_show_action_plan_section?
    menu_show_project_action_plan? || menu_show_achievement_entry? || menu_show_achievement_approvals? ||
      menu_show_vertical_action_plan? || menu_show_vertical_action_plan_record? || menu_show_pis_report_upload? ||
      menu_show_donor_report_upload? || menu_show_fund_report_upload? ||
      %w[po coo director].any? { |stage| menu_show_action_plan_approval?(stage) }
  end
end

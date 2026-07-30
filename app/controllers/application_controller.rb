class ApplicationController < ActionController::Base
  helper_method :current_user, :pending_project_summary_approval_count

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
    return ProjectSummarySubmission.where(status: "pending").count if current_user.admin? || ProjectSummarySubmission.summary_viewer?(current_user.employee)
    return ProjectSummarySubmission.where(status: "pending", approver: current_user.employee).count if ProjectSummarySubmission.summary_approver?(current_user.employee)

    0
  end
end

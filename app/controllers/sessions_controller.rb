class SessionsController < ApplicationController
  def new
    redirect_to after_login_path(current_user) if current_user
  end

  def create
    user = User.find_by(login: params[:login].to_s.strip)

    if user&.authenticate(params[:password].to_s) && user_active?(user)
      session[:user_id] = user.id
      redirect_to after_login_path(user), notice: "Welcome back."
    elsif user&.authenticate(params[:password].to_s)
      flash.now[:alert] = "Your employee login is inactive."
      render :new, status: :unprocessable_entity
    else
      flash.now[:alert] = "Invalid employee ID/email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out successfully."
  end

  private

  def after_login_path(user)
    return admin_employees_path if user.admin?
    return project_summary_approvals_path if ProjectSummarySubmission.summary_access?(user.employee)

    plan_submissions_path
  end

  def user_active?(user)
    user.admin? || user.employee&.active?
  end
end

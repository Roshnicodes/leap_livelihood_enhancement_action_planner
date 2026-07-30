class DashboardController < ApplicationController
  before_action :require_login
  before_action :redirect_admin

  def index
    redirect_to plan_submissions_path and return

    @mode = params[:mode].presence_in(%w[vertical project]) || "vertical"
    @employee = current_user.employee
    @verticals = @employee.verticals
    @projects = @employee.projects
    @filter_options = filter_options
    @selected = selected_filter
    @activities = filtered_activities
    @saved_items_by_activity_id = saved_items_by_activity_id
    @summary = activity_summary(@activities)
  end

  private

  def redirect_admin
    redirect_to admin_employees_path if current_user.admin?
  end

  def filter_options
    @mode == "project" ? @verticals : @projects
  end

  def selected_filter
    params[:filter].presence_in(@filter_options) || @filter_options.first
  end

  def filtered_activities
    scope = @employee.bli_activities.order(:project_name, :vertical_name, :activity_name)
    return scope.none if @selected.blank?

    @mode == "project" ? scope.for_vertical(@selected) : scope.for_project(@selected)
  end

  def activity_summary(scope)
    {
      activities: scope.count,
      allocated: scope.sum(:allocated_fund),
      utilised: scope.sum(:utilised_fund),
      remaining: scope.sum(:remaining_fund),
      pending_pdo: scope.sum(:pending_pdo_count),
      pending_rfp: scope.sum(:pending_rfp_count)
    }
  end

  def saved_items_by_activity_id
    submission = @employee.plan_submissions
      .includes(:plan_submission_items)
      .where(mode: @mode, filter_name: @selected)
      .order(submitted_at: :desc)
      .first

    (submission&.plan_submission_items || []).index_by(&:bli_activity_id)
  end
end

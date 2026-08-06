class ActionPlansController < ApplicationController
  include ActionPlanPresenter
  include ActionPlanSubmitting

  before_action :require_login

  def index
    @project_options = project_options_for_viewer
    @selected_project = params[:project].to_s.presence_in(@project_options)
    @project_ownership = project_ownership_for(@selected_project) unless current_user.admin?
    @rows = action_plan_rows_for(@selected_project)
    @theme_count = @rows.distinct.count(:theme) if @selected_project.present?
    @existing_submission = existing_submission_for(@selected_project)
    @balance_warning = unbalanced_rows_message(@rows) if @selected_project.present?
    @show_achievement = current_user.admin?
    @show_submission = !current_user.admin? && @selected_project.present? && ProjectOwnership.owned?(current_user.employee, @selected_project)
    @editable_targets = false
    @fco_view = @selected_project.present? && fco_scoped_action_plan?(@selected_project)
  end

  def create
    project_name = params[:project_name].to_s

    unless current_user.employee && ProjectOwnership.owned?(current_user.employee, project_name)
      redirect_to action_plans_path, alert: "You do not have access to this project."
      return
    end

    submit_action_plan(
      project_name: project_name,
      rows: action_plan_rows_for(project_name),
      redirect_path: action_plans_path(project: project_name)
    )
  end
end

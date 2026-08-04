class ActionPlansController < ApplicationController
  include ActionPlanPresenter

  before_action :require_login

  def index
    @project_options = project_options_for_viewer
    @selected_project = params[:project].to_s.presence_in(@project_options)
    @project_ownership = project_ownership_for(@selected_project) unless current_user.admin?
    @rows = action_plan_rows_for(@selected_project)
    @theme_count = @rows.distinct.count(:theme) if @selected_project.present?
    @existing_submission = current_user.employee.action_plan_submissions.where(project_name: @selected_project).order(submitted_at: :desc).first if @selected_project.present?
    @show_achievement = true
    @show_submission = !current_user.admin?
    @editable_targets = false
  end

  def create
    project_name = params[:project_name].to_s

    unless ProjectOwnership.owned?(current_user.employee, project_name)
      redirect_to action_plans_path, alert: "You do not have access to this project."
      return
    end

    project_row = action_plan_rows_for(project_name).order(:id).first

    unless project_row
      redirect_to action_plans_path, alert: "Please choose a valid project."
      return
    end

    ownership = project_ownership_for(project_name) ||
      ProjectOwnership.find_by(po_id: project_row.po_id, project_name: project_name) ||
      ProjectOwnership.find_by(project_name: project_name)

    submission = current_user.employee.action_plan_submissions
      .where.not(status: "approved")
      .where(project_name: project_name)
      .order(submitted_at: :desc)
      .first_or_initialize

    submission.assign_attributes(
      project_ownership: ownership,
      po_id: project_row.po_id,
      project_name: project_name,
      submission_remark: params[:submission_remark].to_s.strip,
      status: "pending",
      current_stage: "po",
      submitted_at: Time.current,
      po_reviewed_at: nil,
      coo_reviewed_at: nil,
      director_reviewed_at: nil,
      po_remark: nil,
      coo_remark: nil,
      director_remark: nil
    )

    if submission.save
      redirect_to action_plans_path(project: project_name), notice: "Action plan sent for PO approval."
    else
      redirect_to action_plans_path(project: project_name), alert: submission.errors.full_messages.to_sentence
    end
  end
end

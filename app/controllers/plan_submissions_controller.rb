class PlanSubmissionsController < ApplicationController
  before_action :require_login

  def index
    @activities = activity_scope
    @project_options = @activities.map(&:project_name).compact_blank.uniq.sort
    @selected_project = params[:project].presence_in(@project_options)
    @activities = @activities.select { |activity| activity.project_name == @selected_project } if @selected_project.present?
    @record_groups = @activities.group_by(&:project_name)
  end

  def create
    employee = current_user.employee
    activities = employee.bli_activities.where(id: item_params.map { |item| item[:bli_activity_id] })
    activities_by_id = activities.index_by { |activity| activity.id.to_s }
    original_total = activities.sum(:allocated_fund)
    changed_total = item_params.sum { |item| BigDecimal(item[:changed_fund].presence || "0") }

    submission = employee.plan_submissions.find_or_initialize_by(
      mode: params[:mode],
      filter_name: params[:filter_name]
    )

    submission.assign_attributes(
      mode: params[:mode],
      filter_name: params[:filter_name],
      original_total: original_total,
      changed_total: changed_total,
      submitted_at: Time.current
    )

    submission.plan_submission_items.destroy_all if submission.persisted?

    item_params.each do |item|
      activity = activities_by_id[item[:bli_activity_id].to_s]
      next unless activity

      submission.plan_submission_items.build(
        bli_activity: activity,
        original_fund: activity.allocated_fund,
        changed_fund: item[:changed_fund],
        remark: item[:remark]
      )
    end

    if submission.save
      redirect_to plan_submissions_path, notice: "Plan submitted successfully."
    else
      redirect_to dashboard_path(mode: params[:mode], filter: params[:filter_name]), alert: submission.errors.full_messages.to_sentence
    end
  rescue ArgumentError
    redirect_to dashboard_path(mode: params[:mode], filter: params[:filter_name]), alert: "Invalid changed fund value."
  end

  private

  def activity_scope
    return global_unique_activities if current_user.admin? || ProjectSummarySubmission.summary_access?(current_user.employee)

    current_user.employee.accessible_bli_activities
  end

  def global_unique_activities
    BliActivity
      .order(:project_name, :vertical_name, :activity_name, :bli_code, :id)
      .to_a
      .uniq { |activity| [ activity.project_name, activity.vertical_name, activity.bli_code, activity.name, activity.activity_name, activity.allocated_fund ] }
  end

  def submission_scope
    current_user.admin? ? PlanSubmission.all : current_user.employee.plan_submissions
  end

  def item_params
    params.fetch(:items, {}).values.map do |item|
      item.permit(:bli_activity_id, :changed_fund, :remark)
    end
  end
end

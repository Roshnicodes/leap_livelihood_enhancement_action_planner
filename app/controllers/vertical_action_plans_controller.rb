class VerticalActionPlansController < ApplicationController
  include ActionPlanPresenter

  before_action :require_login
  before_action :require_vertical_mapping, only: :update

  def index
    @project_options = vertical_project_options
    @selected_project = params[:project].to_s.presence_in(@project_options)
    @vertical_labels = action_plan_vertical_names
    @rows = action_plan_rows_for(@selected_project, vertical_filter: true)
    @theme_count = @rows.distinct.count(:theme) if @selected_project.present?
    @show_achievement = true
    @show_submission = false
    @editable_targets = true
  end

  def update
    project_name = params[:project].to_s
    unless project_name.in?(vertical_project_options)
      redirect_to vertical_action_plans_path, alert: "You do not have access to this project."
      return
    end

    allowed_rows = action_plan_rows_for(project_name, vertical_filter: true).index_by(&:id)
    updated_count = 0

    ActionPlanRow.transaction do
      target_row_params.each do |row_id, months|
        row = allowed_rows[row_id.to_i]
        next unless row

        ActionPlanRow::MONTH_COLUMNS.each do |month|
          row.public_send("#{month}=", integer_value(months[month.to_s]))
        end

        row.save!
        updated_count += 1
      end
    end

    redirect_to vertical_action_plans_path(project: project_name),
      notice: "#{updated_count} #{"row".pluralize(updated_count)} updated."
  rescue ArgumentError
    redirect_to vertical_action_plans_path(project: project_name), alert: "Invalid target value."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to vertical_action_plans_path(project: project_name), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def require_vertical_mapping
    return if action_plan_vertical_names.present?

    redirect_to vertical_action_plans_path, alert: "No parent activity mapping found for your account."
  end

  def target_row_params
    params.fetch(:rows, {}).permit!.to_h
  end

  def integer_value(raw)
    Integer(raw.presence || 0)
  rescue ArgumentError
    raise ArgumentError, "invalid integer"
  end
end

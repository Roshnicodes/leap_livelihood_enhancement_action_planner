class VerticalActionPlansController < ApplicationController
  include ActionPlanPresenter
  include ActionPlanSubmitting

  before_action :require_login
  before_action :require_vertical_mapping, only: %i[update create]

  def index
    @project_options = vertical_project_options
    @selected_project = params[:project].to_s.presence_in(@project_options)
    @vertical_labels = action_plan_vertical_names
    @rows = action_plan_rows_for(@selected_project, vertical_filter: true)
    @theme_count = @rows.distinct.count(:theme) if @selected_project.present?
    @existing_submission = existing_submission_for(@selected_project, plan_type: "vertical")
    @balance_warning = unbalanced_rows_message(@rows) if @selected_project.present?
    @show_achievement = false
    @show_submission = !current_user.admin?
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

    if params[:submit_to_record].present?
      redirect_to action_plan_records_path(project: project_name), notice: "Vertical action plan saved to record."
      return
    end

    redirect_to vertical_action_plans_path(project: project_name),
      notice: save_notice(project_name, updated_count)
  rescue ArgumentError
    redirect_to vertical_action_plans_path(project: project_name), alert: "Invalid target value."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to vertical_action_plans_path(project: project_name), alert: error.record.errors.full_messages.to_sentence
  end

  def create
    project_name = params[:project_name].to_s

    unless project_name.in?(vertical_project_options)
      redirect_to vertical_action_plans_path, alert: "You do not have access to this project."
      return
    end

    submit_action_plan(
      project_name: project_name,
      rows: action_plan_rows_for(project_name, vertical_filter: true),
      redirect_path: vertical_action_plans_path(project: project_name),
      plan_type: "vertical"
    )
  end

  private

  def save_notice(project_name, updated_count)
    saved = "#{updated_count} #{"row".pluralize(updated_count)} updated."
    imbalance = unbalanced_rows_message(action_plan_rows_for(project_name, vertical_filter: true))

    [ saved, imbalance ].compact_blank.join(" ")
  end

  def require_vertical_mapping
    return if current_user.admin? || action_plan_vertical_names.present?

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

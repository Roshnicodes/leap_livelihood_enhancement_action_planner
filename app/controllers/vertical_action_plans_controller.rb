require "csv"

class VerticalActionPlansController < ApplicationController
  include ActionPlanPresenter
  include ActionPlanSubmitting

  before_action :require_login
  before_action :require_employee_action_plan_edit_access, only: %i[update create]
  before_action :require_vertical_mapping, only: %i[update create]

  def index
    @project_options = vertical_project_options
    @selected_project = params[:project].to_s.presence_in([ "all", *@project_options ])
    @fco_options = action_plan_filter_options(@selected_project, :user_name, :user_id)
    @selected_fco_id = params[:fco_id].to_s.presence_in(@fco_options.map(&:last))
    @to_options = action_plan_filter_options(@selected_project, :to_name, :to_id, fco_id: @selected_fco_id)
    @selected_to_id = params[:to_id].to_s.presence_in(@to_options.map(&:last))
    @vertical_labels = action_plan_vertical_names
    @rows = action_plan_rows_for(@selected_project, vertical_filter: true, fco_id: @selected_fco_id, to_id: @selected_to_id)
    @project_ownership = project_ownership_for(@selected_project) if @selected_project != "all"
    @project_ownership_lookup = project_ownership_lookup_for(@rows) if current_user.admin?
    @theme_count = @rows.distinct.count(:theme) if @selected_project.present?
    @existing_submission = existing_submission_for(@selected_project, plan_type: "vertical") if @selected_project != "all"
    @balance_warning = unbalanced_rows_message(@rows) if @selected_project.present? && @selected_project != "all"
    @show_achievement = false
    @show_submission = !current_user.admin? && @selected_project != "all"
    @editable_targets = !current_user.admin? && @selected_project != "all"
  end

  def download
    project_options = vertical_project_options
    selected_project = params[:project].to_s.presence_in([ "all", *project_options ])
    fco_options = action_plan_filter_options(selected_project, :user_name, :user_id)
    selected_fco_id = params[:fco_id].to_s.presence_in(fco_options.map(&:last))
    to_options = action_plan_filter_options(selected_project, :to_name, :to_id, fco_id: selected_fco_id)
    selected_to_id = params[:to_id].to_s.presence_in(to_options.map(&:last))
    rows = action_plan_rows_for(selected_project, vertical_filter: true, fco_id: selected_fco_id, to_id: selected_to_id)

    csv = vertical_action_plan_csv(rows)
    send_data XlsxWorkbook.from_csv(csv, title: "Vertical Action Plan", sheet_name: "Vertical Plan"),
      filename: "vertical_action_plan_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
      type: XlsxWorkbook::CONTENT_TYPE
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
        ActionPlanMonthChange.capture_row_deltas!(row, changed_by: current_user)
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

  def require_employee_action_plan_edit_access
    return if current_user.employee.present? && !current_user.admin?

    redirect_to vertical_action_plans_path(project: params[:project].presence || params[:project_name].presence), alert: "PMC can view records but cannot edit."
  end

  def target_row_params
    params.fetch(:rows, {}).permit!.to_h
  end

  def project_ownership_lookup_for(rows)
    po_ids = rows.reorder(nil).reselect(:po_id).distinct.pluck(:po_id).compact_blank
    project_names = rows.reorder(nil).reselect(:project_name).distinct.pluck(:project_name).compact_blank
    ownerships = []
    ownerships.concat(ProjectOwnership.where(po_id: po_ids).to_a) if po_ids.any?
    ownerships.concat(ProjectOwnership.where(project_name: project_names).to_a) if project_names.any?

    ownerships.uniq.each_with_object({}) do |ownership, lookup|
      lookup[project_ownership_lookup_key(ownership.po_id, ownership.project_name)] = ownership
      lookup["po:#{ownership.po_id}"] ||= ownership
      lookup["project:#{ProjectOwnership.normalize_project_key(ownership.project_name)}"] ||= ownership
    end
  end

  def project_ownership_lookup_key(po_id, project_name)
    "po_project:#{po_id}:#{ProjectOwnership.normalize_project_key(project_name)}"
  end

  def vertical_action_plan_csv(rows)
    CSV.generate(headers: true) do |csv|
      csv << [
        *ActionPlanRow.display_columns(admin: current_user.admin?).map { |column| column[:header] },
        *ActionPlanRow::MONTH_DISPLAY_PAIRS.flat_map { |pair| [ pair[:target_label], pair[:achievement_label] ] },
        "Total Target",
        "Total Achievement"
      ]

      rows.each do |row|
        csv << [
          *ActionPlanRow.display_columns(admin: current_user.admin?).map { |column| row.public_send(column[:attribute]) },
          *ActionPlanRow::MONTH_DISPLAY_PAIRS.flat_map { |pair| [ row.public_send(pair[:target_column]), row.public_send(pair[:achievement_column]) ] },
          row.monthly_total,
          row.target_total
        ]
      end
    end
  end

  def integer_value(raw)
    Integer(raw.presence || 0)
  rescue ArgumentError
    raise ArgumentError, "invalid integer"
  end
end

require "csv"

class ActionPlansController < ApplicationController
  include ActionPlanPresenter
  include ActionPlanSubmitting

  before_action :require_login

  def index
    @project_options = project_options_for_viewer
    @selected_project = params[:project].to_s.presence_in([ "all", *@project_options ])
    @selected_project ||= "all" if current_user.admin? || @project_options.any?
    @period_options = action_plan_period_options
    @selected_period = selected_period
    @selected_period_month = selected_period_month
    @month_display_pairs = action_plan_month_pairs_for(@selected_period, @selected_period_month)
    @state_options = action_plan_filter_options(@selected_project, :statte, :statte)
    @selected_state = params[:state].to_s.presence_in(@state_options.map(&:last))
    @vertical_options = action_plan_filter_options(@selected_project, :asa_theme, :asa_theme, state_code: @selected_state)
    @selected_vertical = params[:vertical].to_s.presence_in(@vertical_options.map(&:last))
    @fco_options = action_plan_filter_options(@selected_project, :user_name, :user_id, state_code: @selected_state, vertical_name: @selected_vertical)
    @selected_fco_id = params[:fco_id].to_s.presence_in(@fco_options.map(&:last))
    @to_options = action_plan_filter_options(@selected_project, :to_name, :to_id, fco_id: @selected_fco_id, state_code: @selected_state, vertical_name: @selected_vertical)
    @selected_to_id = params[:to_id].to_s.presence_in(@to_options.map(&:last))
    @project_ownership = project_ownership_for(@selected_project) if @selected_project != "all"
    @rows = action_plan_rows_for(@selected_project, fco_id: @selected_fco_id, to_id: @selected_to_id, state_code: @selected_state, vertical_name: @selected_vertical)
    @project_ownership_lookup = project_ownership_lookup_for(@rows) if current_user.admin?
    @theme_count = @rows.distinct.count(:theme) if @selected_project.present?
    @existing_submission = existing_submission_for(@selected_project) if @selected_project != "all"
    @balance_warning = unbalanced_rows_message(@rows) if @selected_project.present?
    @show_achievement = current_user.admin?
    @show_submission = !current_user.admin? && @selected_project.present? && @selected_project != "all" && ProjectOwnership.owned?(current_user.employee, @selected_project)
    @editable_targets = false
    @fco_view = @selected_project.present? && @selected_project != "all" && fco_scoped_action_plan?(@selected_project)
  end

  def download
    project_options = project_options_for_viewer
    selected_project = params[:project].to_s.presence_in([ "all", *project_options ]) || "all"
    state_options = action_plan_filter_options(selected_project, :statte, :statte)
    selected_state = params[:state].to_s.presence_in(state_options.map(&:last))
    vertical_options = action_plan_filter_options(selected_project, :asa_theme, :asa_theme, state_code: selected_state)
    selected_vertical = params[:vertical].to_s.presence_in(vertical_options.map(&:last))
    fco_options = action_plan_filter_options(selected_project, :user_name, :user_id, state_code: selected_state, vertical_name: selected_vertical)
    selected_fco_id = params[:fco_id].to_s.presence_in(fco_options.map(&:last))
    to_options = action_plan_filter_options(selected_project, :to_name, :to_id, fco_id: selected_fco_id, state_code: selected_state, vertical_name: selected_vertical)
    selected_to_id = params[:to_id].to_s.presence_in(to_options.map(&:last))
    rows = action_plan_rows_for(selected_project, fco_id: selected_fco_id, to_id: selected_to_id, state_code: selected_state, vertical_name: selected_vertical)

    month_pairs = action_plan_month_pairs_for(selected_period, selected_period_month)
    csv = project_action_plan_csv(rows, month_pairs: month_pairs)
    send_data XlsxWorkbook.from_csv(csv, title: "Project Action Plan", sheet_name: "Action Plan"),
      filename: "project_action_plan_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
      type: XlsxWorkbook::CONTENT_TYPE
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

  private

  def project_action_plan_csv(rows, month_pairs: ActionPlanRow::MONTH_DISPLAY_PAIRS)
    columns = ActionPlanRow.display_columns(admin: current_user.admin?)
    ownership_lookup = project_ownership_lookup_for(rows)

    CSV.generate(headers: true) do |csv|
      csv << [
        *columns.map { |column| column[:header] },
        *month_pairs.flat_map { |pair| [ pair[:target_label], pair[:achievement_label] ] },
        "Total Target",
        "Total Achievement"
      ]

      rows.each do |row|
        ownership = project_ownership_for_row(row, ownership_lookup)
        csv << [
          *columns.map { |column| project_action_plan_export_value(row, column, ownership) },
          *month_pairs.flat_map { |pair| [ row.public_send(pair[:target_column]), row.public_send(pair[:achievement_column]) ] },
          month_pairs.sum { |pair| row.public_send(pair[:target_column]).to_i },
          month_pairs.sum { |pair| row.public_send(pair[:achievement_column]).to_i }
        ]
      end
    end
  end

  def project_action_plan_export_value(row, column, ownership)
    if current_user.admin? && column[:attribute] == :project_owner
      [ ownership&.po_name, ownership&.project_owner_id ].compact_blank.join(" / ").presence || row.project_owner
    else
      row.public_send(column[:attribute])
    end
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

  def project_ownership_for_row(row, lookup)
    lookup[project_ownership_lookup_key(row.po_id, row.project_name)] ||
      lookup["po:#{row.po_id}"] ||
      lookup["project:#{ProjectOwnership.normalize_project_key(row.project_name)}"]
  end

  def project_ownership_lookup_key(po_id, project_name)
    "po_project:#{po_id}:#{ProjectOwnership.normalize_project_key(project_name)}"
  end
end

module Api
  class ActionPlansController < ApplicationController
    include ActionPlanPresenter

    before_action :require_json_login

    def project
      render json: action_plan_payload(plan_type: "project", vertical_filter: false)
    end

    def vertical
      render json: action_plan_payload(plan_type: "vertical", vertical_filter: true)
    end

    private

    def require_json_login
      return if current_user&.admin? || current_user&.employee&.active?

      reset_session if current_user
      render json: { error: "Please login to continue." }, status: :unauthorized
    end

    def action_plan_payload(plan_type:, vertical_filter:)
      project_options = vertical_filter ? vertical_project_options : project_options_for_viewer
      selected_project = params[:project].to_s.presence_in([ "all", *project_options ])
      selected_project ||= "all" if current_user.admin? || project_options.any?
      state_options = api_action_plan_filter_options(selected_project, :statte, :statte, vertical_filter: vertical_filter)
      selected_state = params[:state].to_s.presence_in(state_options.map(&:last))
      vertical_options = api_action_plan_filter_options(selected_project, :asa_theme, :asa_theme, vertical_filter: vertical_filter, state_code: selected_state)
      selected_vertical = params[:vertical].to_s.presence_in(vertical_options.map(&:last))
      fco_options = api_action_plan_filter_options(selected_project, :user_name, :user_id, vertical_filter: vertical_filter, state_code: selected_state, vertical_name: selected_vertical)
      selected_fco_id = params[:fco_id].to_s.presence_in(fco_options.map(&:last))
      to_options = api_action_plan_filter_options(selected_project, :to_name, :to_id, vertical_filter: vertical_filter, fco_id: selected_fco_id, state_code: selected_state, vertical_name: selected_vertical)
      selected_to_id = params[:to_id].to_s.presence_in(to_options.map(&:last))
      month_pairs = action_plan_month_pairs_for(selected_period, selected_period_month)
      rows = action_plan_rows_for(
        selected_project,
        vertical_filter: vertical_filter,
        fco_id: selected_fco_id,
        to_id: selected_to_id,
        state_code: selected_state,
        vertical_name: selected_vertical
      )

      {
        plan_type: plan_type,
        filters: {
          project: selected_project,
          state: selected_state,
          vertical: selected_vertical,
          fco_id: selected_fco_id,
          to_id: selected_to_id,
          period: selected_period,
          period_month: selected_period_month
        },
        options: {
          projects: project_options,
          states: option_payload(state_options),
          verticals: option_payload(vertical_options),
          fcos: option_payload(fco_options),
          tos: option_payload(to_options),
          periods: option_payload(action_plan_period_options)
        },
        columns: month_pairs.map do |pair|
          {
            month: pair[:target_column],
            target_label: pair[:target_label],
            achievement_label: pair[:achievement_label]
          }
        end,
        summary: {
          row_count: rows.count,
          total_target: rows.to_a.sum(&:monthly_total),
          total_achievement: rows.to_a.sum(&:target_total)
        },
        rows: rows.map { |row| row_payload(row, month_pairs) }
      }
    end

    def api_action_plan_filter_options(project_name, label_attribute, value_attribute, vertical_filter:, fco_id: nil, to_id: nil, state_code: nil, vertical_name: nil)
      rows = action_plan_rows_for(
        project_name.presence || "all",
        vertical_filter: vertical_filter,
        state_code: state_code,
        vertical_name: vertical_name
      )
      rows = rows.where(user_id: fco_filter_ids(fco_id)) if fco_id.present?
      rows = rows.where(to_id: to_id) if to_id.present?

      return fco_filter_options_for(rows) if value_attribute.to_sym == :user_id

      rows
        .where.not(value_attribute => [ nil, "" ])
        .distinct
        .reorder(label_attribute, value_attribute)
        .pluck(label_attribute, value_attribute)
        .map { |label, value| [ label.presence || value.to_s, value.to_s ] }
    end

    def option_payload(options)
      options.map { |label, value| { label: label, value: value } }
    end

    def row_payload(row, month_pairs)
      {
        id: row.id,
        id_new: row.id_new,
        state: row.statte,
        po_id: row.po_id,
        project_id: row.project_id,
        project_name: row.project_name,
        project_owner: row.project_owner,
        fco_id: row.user_id,
        fco_name: row.user_name,
        to_id: row.to_id,
        to_name: row.to_name,
        asa_theme_id: row.asa_theme_id,
        asa_theme: row.asa_theme,
        asa_activity_id: row.asa_activity_id,
        asa_activity_name: row.asa_activity_name,
        project_theme_id: row.theme_id,
        project_theme: row.theme,
        project_activity_id: row.activity_id,
        project_activity: row.activity,
        unit_type: row.unit_type,
        admin_remark: current_user.admin? ? row.a_remark : nil,
        months: month_pairs.each_with_object({}) do |pair, month_values|
          month_values[pair[:target_column]] = {
            target: row.public_send(pair[:target_column]),
            achievement: row.public_send(pair[:achievement_column])
          }
        end,
        total_target: month_pairs.sum { |pair| row.public_send(pair[:target_column]).to_i },
        total_achievement: month_pairs.sum { |pair| row.public_send(pair[:achievement_column]).to_i }
      }
    end
  end
end

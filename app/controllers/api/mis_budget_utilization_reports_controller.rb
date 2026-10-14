module Api
  # JSON copy of P&B > MIS Budget Utilization. Reuses the web report's filters
  # and row building, so the API and the page always show the same numbers.
  # Same filters as the page: project, vertical, office, user, period, period_month.
  class MisBudgetUtilizationReportsController < ::MisBudgetUtilizationReportsController
    include ApiKeyAuthentication
    skip_before_action :require_login, :require_admin
    before_action :require_json_admin

    def index
      prepare_filters
      rows = @latest_month.present? ? report_rows : []
      allocated_total = rows.sum { |row| row[:month_allocated].values.sum(&:to_d) }
      expenditure_total = rows.sum { |row| row[:total_expenditure].to_d }

      render json: {
        filters: {
          project: @selected_project,
          vertical: @selected_vertical,
          office: @selected_office,
          user: @selected_user,
          period: @selected_period,
          period_month: @selected_period_month,
          latest_saved_month: @latest_month
        },
        options: {
          projects: [ "all", *@project_options ],
          verticals: @vertical_options,
          offices: @office_options,
          users: @user_options,
          periods: @period_options.map { |label, value| { label: label, value: value } }
        },
        months: @months,
        summary: {
          row_count: rows.size,
          project_count: rows.map { |row| row[:project_name] }.compact_blank.uniq.size,
          allocated_total: allocated_total.to_f,
          expenditure_total: expenditure_total.to_f,
          remaining_total: (allocated_total - expenditure_total).to_f
        },
        rows: rows.each_with_index.map { |row, index| row_payload(row, index) }
      }
    end

    private

    def require_json_admin
      return if current_user&.admin?

      render json: { error: current_user ? "MIS access required." : "Please login to continue." },
        status: current_user ? :forbidden : :unauthorized
    end

    def row_payload(row, index)
      {
        s_no: index + 1,
        project_name: row[:project_name],
        project_bli_name: row[:project_bli_name],
        bli_code: row[:bli_code],
        allocated_fund: row[:allocated_fund].to_f,
        financial_year: row[:financial_year],
        office_name: row[:office_name],
        vertical_name: row[:vertical_name],
        activity_name: row[:activity_name],
        responsible_user_name: row[:responsible_user_name],
        total_expenditure: row[:total_expenditure].to_d.round(2).to_f,
        total_remaining: row[:total_remaining].to_d.round(2).to_f,
        months: @months.map do |month|
          {
            month: month,
            allocated: row[:month_allocated][month].to_d.round(2).to_f,
            expenses: row[:month_utilized][month].to_d.round(2).to_f
          }
        end
      }
    end
  end
end

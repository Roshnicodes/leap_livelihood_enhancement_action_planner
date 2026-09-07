require "csv"

class BudgetUtilizationReportsController < ApplicationController
  before_action :require_login

  MONTH_KEYS = BudgetUtilization::MONTH_KEYS

  def index
    @latest_month = BudgetUtilization.latest_saved_month
    @report_columns = @latest_month.present? ? BudgetUtilization.report_columns_through(@latest_month) : []
    @rows = @latest_month.present? ? report_rows_for_all_projects : []
    @project_total = @rows.sum { |row| row[:total_allocated].to_d }
    @expenditure_total = @rows.sum { |row| row[:total_expenditure].to_d }
    @remaining_total = @project_total - @expenditure_total

    respond_to do |format|
      format.html
      format.csv do
        send_data budget_report_csv,
          filename: "budget_utilization_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(budget_report_csv, title: "Budget Utilization Report", sheet_name: "Budget Report"),
          filename: "budget_utilization_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  private

  def report_rows_for_all_projects
    months = MONTH_KEYS[0..MONTH_KEYS.index(@latest_month)]
    project_names = BudgetUtilization.submitted.with_single_bli_code.distinct.order(:project_name).pluck(:project_name).compact_blank
    return [] if project_names.blank?

    utilizations = BudgetUtilization.submitted.with_single_bli_code.includes(:submitted_by, :updated_by).where(project_name: project_names, month: months)
      .group_by(&:project_name)

    project_names.filter_map do |project_name|
      project_utilizations = utilizations[project_name] || []
      next if project_utilizations.blank?

      row = project_row(project_name, months, project_utilizations)
      next if row[:total_expenditure].to_d.zero?

      row
    end
  end

  def project_row(project_name, months, project_utilizations)
    activities = BliActivity.active.with_single_bli_code.where(project_name: project_name)
    return if activities.none?

    total_allocated = activities
      .group_by(&:bli_code)
      .sum { |_code, grouped| grouped.map { |activity| activity.allocated_fund.to_d }.max }

    by_month = project_utilizations.group_by(&:month)
    month_utilized = months.index_with do |month|
      (by_month[month] || []).sum { |record| record.utilized_amount.to_d }
    end
    month_audit = months.index_with do |month|
      month_audit_line(by_month[month] || [])
    end
    latest_submission = project_utilizations.filter_map(&:submitted_at).max
    submitters = project_utilizations.map { |record| user_label(record.submitted_by) }.reject { |label| label == "-" }.uniq
    total_expenditure = month_utilized.values.sum

    {
      project_name: project_name,
      total_allocated: total_allocated,
      month_utilized: month_utilized,
      month_audit: month_audit,
      total_expenditure: total_expenditure,
      total_remaining: total_allocated - total_expenditure,
      submitted_by: submitters.to_sentence,
      submitted_at: latest_submission
    }
  end

  def budget_report_csv
    CSV.generate(headers: true) do |csv|
      csv << [
        "S.No.",
        "Project",
        "Total Allocated Budget",
        "Total Expenditure",
        "Total Remaining Budget",
        "Last Submitted By",
        "Last Submitted At",
        *@report_columns.flat_map { |column| budget_report_column_headers(column) }
      ]

      @rows.each_with_index do |row, index|
        csv << [
          index + 1,
          row[:project_name],
          row[:total_allocated],
          row[:total_expenditure],
          row[:total_remaining],
          row[:submitted_by],
          format_datetime(row[:submitted_at]),
          *@report_columns.flat_map { |column| budget_report_column_values(row, column) }
        ]
      end
    end
  end

  def budget_report_column_headers(column)
    return [ column[:label], "#{column[:label]} Submitted Details" ] if column[:type] == :month

    [ column[:label] ]
  end

  def budget_report_column_values(row, column)
    if column[:type] == :month
      [ row[:month_utilized][column[:key]].to_d, row[:month_audit][column[:key]] ]
    else
      [ column[:months].sum { |month| row[:month_utilized][month].to_d } ]
    end
  end

  def month_audit_line(records)
    records = records.compact
    return if records.blank?

    submitted_times = records.filter_map(&:submitted_at)
    submitters = records.map { |record| user_label(record.submitted_by) }.reject { |label| label == "-" }.uniq
    return "Submitted by #{submitters.to_sentence}" if submitted_times.blank?

    first_time = submitted_times.min
    last_time = submitted_times.max
    first_label = format_datetime(first_time)
    last_label = format_datetime(last_time)
    time_label = first_label == last_label ? first_label : "#{first_label} - #{last_label}"

    submitters.present? ? "Submitted #{time_label} by #{submitters.to_sentence}" : "Submitted #{time_label}"
  end

  def user_label(user)
    return "-" if user.blank?

    employee = user.employee
    return [ employee.employee_code, employee.name ].compact_blank.join(" - ") if employee.present?

    user.login.presence || "User ##{user.id}"
  end

  def format_datetime(timestamp)
    timestamp&.in_time_zone("Asia/Kolkata")&.strftime("%d %b %Y, %I:%M %p")
  end
end

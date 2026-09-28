require "csv"

class MisBudgetUtilizationReportsController < ApplicationController
  before_action :require_login
  before_action :require_admin

  MONTH_KEYS = BudgetUtilization::MONTH_KEYS
  PROTECTION_PASSWORD = ENV.fetch("MIS_BUDGET_REPORT_PASSWORD", "mis@123").freeze

  def index
    @latest_month = BudgetUtilization.latest_saved_month
    @months = @latest_month.present? ? MONTH_KEYS[0..MONTH_KEYS.index(@latest_month)] : []
    @quarter_columns = @latest_month.present? ? BudgetUtilization.report_columns_through(@latest_month).select { |column| column[:type] == :quarter } : []
    @rows = @latest_month.present? ? report_rows : []
    @project_total = @rows.sum { |row| row[:allocated_fund].to_d }
    @expenditure_total = @rows.sum { |row| row[:total_expenditure].to_d }
    @remaining_total = @project_total - @expenditure_total
    @project_count = @rows.map { |row| row[:project_name] }.compact_blank.uniq.size

    respond_to do |format|
      format.html
      format.csv do
        send_data budget_report_csv,
          filename: "mis_budget_utilization_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(
          budget_report_csv,
          title: "MIS Budget Utilization Report",
          sheet_name: "MIS Budget Report",
          protected: true,
          protection_password: PROTECTION_PASSWORD
        ),
          filename: "mis_budget_utilization_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  private

  def report_rows
    activities = BliActivity.active.includes(:employee).order(:project_name, :bli_code, :name, :activity_name, :vertical_name, :id).to_a
    utilizations = BudgetUtilization.submitted.with_single_bli_code.includes(:submitted_by).where(month: @months)
      .group_by { |record| [ record.project_name, record.bli_code.to_s, record.month ] }
    allocation_totals_by_key = activities.group_by { |activity| activity_key(activity) }
      .transform_values { |grouped| grouped.sum { |activity| activity.allocated_fund.to_d } }

    activities.map do |activity|
      build_activity_row(activity, utilizations, allocation_totals_by_key)
    end
  end

  def build_activity_row(activity, utilizations, allocation_totals_by_key)
    month_allocated = @months.index_with { |month| month_amount_for(activity.allocated_fund.to_d, activity.vertical_name, month) }
    month_utilized = @months.index_with do |month|
      utilization_share_for(activity, utilizations[[ activity.project_name, activity.bli_code.to_s, month ]] || [], allocation_totals_by_key)
    end
    month_audit = @months.index_with do |month|
      month_audit_line(utilizations[[ activity.project_name, activity.bli_code.to_s, month ]] || [])
    end
    total_expenditure = month_utilized.values.sum

    {
      project_bli_name: activity.name,
      bli_code: activity.bli_code,
      allocated_fund: activity.allocated_fund.to_d,
      financial_year: activity.financial_year,
      project_name: activity.project_name,
      office_name: office_name_for(activity),
      vertical_name: activity.vertical_name,
      activity_name: activity.activity_name,
      responsible_user_name: activity.responsible_user_name,
      month_allocated: month_allocated,
      month_utilized: month_utilized,
      month_audit: month_audit,
      total_expenditure: total_expenditure,
      total_remaining: activity.allocated_fund.to_d - total_expenditure
    }
  end

  def office_name_for(activity)
    activity.office_name.presence ||
      activity.employee&.office_name.presence ||
      [ activity.employee&.branch, activity.employee&.sub_branch ].compact_blank.join(" / ").presence
  end

  def utilization_share_for(activity, records, allocation_totals_by_key)
    return 0.to_d if records.blank? || !BliActivity.single_bli_code?(activity.bli_code)

    total_allocated_for_code = allocation_totals_by_key[activity_key(activity)].to_d
    return 0.to_d if total_allocated_for_code.zero?

    records.sum { |record| record.utilized_amount.to_d } * activity.allocated_fund.to_d / total_allocated_for_code
  end

  def activity_key(activity)
    [ activity.project_name, activity.bli_code.to_s ]
  end

  def month_amount_for(total_amount, vertical_name, month)
    percent = vertical_percent_for(vertical_name)
    if month == MONTH_KEYS.last
      earlier_months = MONTH_KEYS[0...-1].sum do |candidate|
        (total_amount * (percent&.public_send(candidate) || 0) / 100).round(2)
      end
      total_amount - earlier_months
    else
      (total_amount * (percent&.public_send(month) || 0) / 100).round(2)
    end
  end

  def vertical_percent_for(vertical_name)
    @vertical_percents_by_name ||= VerticalPercent.all.index_by(&:vertical_name)
    @vertical_percents_by_name[vertical_name]
  end

  def budget_report_csv
    CSV.generate(headers: true) do |csv|
      csv << budget_report_headers

      @rows.each_with_index do |row, index|
        csv << budget_report_values(row, index)
      end
    end
  end

  def budget_report_headers
    [
      "S.No.",
      "Project Name",
      "Project BLI Name",
      "BLI Code",
      "BLI Allocated Fund",
      "Financial Year",
      "Office Name",
      "Vertical",
      "Activity",
      "Responsible Users",
      "Total Expenditure",
      "Total Remaining Budget",
      *@months.flat_map { |month| [ "#{month.capitalize} Month Allocated Budget", month.capitalize, "#{month.capitalize} Submitted Details" ] },
      *@quarter_columns.map { |column| column[:label] }
    ]
  end

  def budget_report_values(row, index)
    [
      index + 1,
      row[:project_name],
      row[:project_bli_name],
      row[:bli_code],
      row[:allocated_fund],
      row[:financial_year],
      row[:office_name],
      row[:vertical_name],
      row[:activity_name],
      row[:responsible_user_name],
      row[:total_expenditure],
      row[:total_remaining],
      *@months.flat_map { |month| [ row[:month_allocated][month].to_d, row[:month_utilized][month].to_d, row[:month_audit][month] ] },
      *@quarter_columns.map { |column| column[:months].sum { |month| row[:month_utilized][month].to_d } }
    ]
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

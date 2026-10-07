require "csv"

class MisBudgetUtilizationReportsController < ApplicationController
  before_action :require_login
  before_action :require_admin

  MONTH_KEYS = BudgetUtilization::MONTH_KEYS
  PERIOD_FILTER_OPTIONS = ActionPlanPresenter::PERIOD_FILTER_OPTIONS
  QUARTER_MONTHS = ActionPlanPresenter::QUARTER_MONTHS
  def index
    prepare_filters
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
          sheet_name: "MIS Budget Report"
        ),
          filename: "mis_budget_utilization_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  private

  def prepare_filters
    @project_options = filter_values(BliActivity.active, :project_name)
    @selected_project = params[:project].to_s.presence_in([ "all", *@project_options ]) || "all"
    @period_options = PERIOD_FILTER_OPTIONS
    @latest_month = BudgetUtilization.latest_saved_month(project_name: selected_project_filter)
    @latest_month ||= BudgetUtilization.latest_saved_month
    @selected_period = params[:period].to_s.presence_in(PERIOD_FILTER_OPTIONS.map(&:last)) || "till_month"
    @selected_period_month = params[:period_month].to_s.presence_in(MONTH_KEYS) || @latest_month || current_budget_month
    @months = @latest_month.present? ? report_months_for(@selected_period, @selected_period_month) : []

    project_scope = filtered_activity_scope(project: true)
    @vertical_options = filter_values(project_scope, :vertical_name)
    @selected_vertical = params[:vertical].to_s.presence_in(@vertical_options)

    vertical_scope = filtered_activity_scope(project: true, vertical: true)
    @office_options = office_filter_values(vertical_scope)
    @selected_office = params[:office].to_s.presence_in(@office_options)

    office_scope = filtered_activity_scope(project: true, vertical: true)
    office_activities = apply_office_filter(office_scope.includes(:employee).to_a)
    @user_options = office_activities.map(&:responsible_user_name).compact_blank.uniq.sort
    @selected_user = params[:user].to_s.presence_in(@user_options)
  end

  def report_rows
    activities = filtered_activity_scope(project: true, vertical: true, user: true)
      .includes(:employee)
      .order(:project_name, :bli_code, :name, :activity_name, :vertical_name, :id)
      .to_a
    activities = apply_office_filter(activities)
    utilizations = filtered_utilization_scope.where(month: @months)
      .group_by { |record| [ record.project_name, record.bli_code.to_s, record.month ] }
    allocation_totals_by_key = BliActivity.active.group_by { |activity| activity_key(activity) }
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
      total_expenditure: total_expenditure,
      total_remaining: activity.allocated_fund.to_d - total_expenditure
    }
  end

  def office_name_for(activity)
    activity.office_name.presence ||
      activity.employee&.office_name.presence ||
      [ activity.employee&.branch, activity.employee&.sub_branch ].compact_blank.join(" / ").presence
  end

  def office_filter_name_for(activity)
    office_filter_label(office_name_for(activity))
  end

  def office_filter_label(value)
    parts = value.to_s.split("/").map { |part| normalize_office_filter_part(part) }.compact_blank.uniq
    parts.join(" / ").presence
  end

  def normalize_office_filter_part(value)
    value.to_s.squish.gsub(/\s*-\s*/, "-")
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
      *@months.flat_map { |month| [ "#{month.capitalize} Month Allocated Budget", "#{month.capitalize} Expenses" ] }
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
      *@months.flat_map { |month| [ row[:month_allocated][month].to_d, row[:month_utilized][month].to_d ] }
    ]
  end

  def filter_values(scope, column)
    scope
      .where.not(column => [ nil, "" ])
      .distinct
      .order(column)
      .pluck(column)
  end

  def filtered_activity_scope(project: false, vertical: false, user: false)
    scope = BliActivity.active
    scope = scope.where(project_name: @selected_project) if project && selected_project_filter.present?
    scope = scope.where(vertical_name: @selected_vertical) if vertical && @selected_vertical.present?
    scope = scope.where(responsible_user_name: @selected_user) if user && @selected_user.present?
    scope
  end

  def filtered_utilization_scope
    scope = BudgetUtilization.submitted.with_single_bli_code
    scope = scope.where(project_name: @selected_project) if selected_project_filter.present?
    scope = scope.where(vertical_name: @selected_vertical) if @selected_vertical.present?
    scope
  end

  def selected_project_filter
    @selected_project if @selected_project.present? && @selected_project != "all"
  end

  def office_filter_values(scope)
    scope
      .includes(:employee)
      .to_a
      .map { |activity| office_filter_name_for(activity) }
      .compact_blank
      .uniq
      .sort
  end

  def apply_office_filter(activities)
    return activities if @selected_office.blank?

    activities.select { |activity| office_filter_name_for(activity) == @selected_office }
  end

  def report_months_for(period, month)
    month = month.presence_in(MONTH_KEYS) || current_budget_month
    index = MONTH_KEYS.index(month) || 0

    case period
    when "monthly"
      [ month ]
    when *QUARTER_MONTHS.keys
      QUARTER_MONTHS.fetch(period)
    when "half_yearly"
      index < 6 ? MONTH_KEYS.first(6) : MONTH_KEYS.last(6)
    when "yearly"
      MONTH_KEYS
    else
      MONTH_KEYS[0..index]
    end
  end

  def current_budget_month
    Date.current.strftime("%b").downcase.presence_in(MONTH_KEYS) || MONTH_KEYS.first
  end
end

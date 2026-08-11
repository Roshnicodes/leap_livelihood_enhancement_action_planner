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
  end

  private

  def report_rows_for_all_projects
    months = MONTH_KEYS[0..MONTH_KEYS.index(@latest_month)]
    project_names = BudgetUtilization.submitted.with_single_bli_code.distinct.order(:project_name).pluck(:project_name).compact_blank
    return [] if project_names.blank?

    utilizations = BudgetUtilization.submitted.with_single_bli_code.where(project_name: project_names, month: months)
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
    activities = BliActivity.with_single_bli_code.where(project_name: project_name)
    return if activities.none?

    total_allocated = activities
      .group_by(&:bli_code)
      .sum { |_code, grouped| grouped.map { |activity| activity.allocated_fund.to_d }.max }

    by_month = project_utilizations.group_by(&:month)
    month_utilized = months.index_with do |month|
      (by_month[month] || []).sum { |record| record.utilized_amount.to_d }
    end
    total_expenditure = month_utilized.values.sum

    {
      project_name: project_name,
      total_allocated: total_allocated,
      month_utilized: month_utilized,
      total_expenditure: total_expenditure,
      total_remaining: total_allocated - total_expenditure
    }
  end
end

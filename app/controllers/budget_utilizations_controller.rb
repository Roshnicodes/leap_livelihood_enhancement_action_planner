class BudgetUtilizationsController < ApplicationController
  before_action :require_login
  before_action :require_budget_utilization_edit_access, only: :update

  MONTH_OPTIONS = BudgetUtilization::MONTH_KEYS.map { |month| [ month.capitalize, month ] }.freeze
  MONTH_KEYS = BudgetUtilization::MONTH_KEYS

  def index
    load_budget_workspace
  end

  def update
    load_budget_workspace

    if @selected_project.blank? || @selected_month.blank?
      redirect_to budget_utilizations_path, alert: "Please choose project and month."
      return
    end

    if @submitted_locked
      redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "This budget utilization is already submitted. Changes are locked."
      return
    end

    final_submit = params[:commit].to_s == "Submit Final"
    if final_submit && !@has_draft
      redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "Please save draft first. After checking the draft, submit final."
      return
    end

    BudgetUtilization.transaction do
      params.fetch(:utilizations, {}).each_value do |row_params|
        attrs = row_params.permit(:project_name, :activity_name, :vertical_name, :bli_code, :planned_amount, :utilized_amount)
        utilization = BudgetUtilization.find_or_initialize_by(
          project_name: attrs[:project_name],
          bli_code: attrs[:bli_code].to_s,
          month: @selected_month
        )
        utilization.assign_attributes(
          activity_name: attrs[:activity_name],
          vertical_name: attrs[:vertical_name],
          planned_amount: decimal(attrs[:planned_amount]),
          utilized_amount: decimal(attrs[:utilized_amount]),
          updated_by: current_user,
          status: final_submit ? "submitted" : "draft",
          submitted_at: final_submit ? Time.current : nil,
          submitted_by: final_submit ? current_user : nil
        )
        utilization.save!
      end
    end

    notice = final_submit ? "Budget utilization submitted. Changes are now locked." : "Budget utilization draft saved. Review it, then submit final."
    redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def require_budget_utilization_edit_access
    return if BudgetUtilization.finance_user?(current_user)

    redirect_to budget_utilizations_path(project: params[:project], month: params[:month]), alert: "Only Accounts can update budget utilization."
  end

  def load_budget_workspace
    @can_edit = BudgetUtilization.finance_user?(current_user)
    @month_options = MONTH_OPTIONS
    @project_options = activity_scope.where.not(project_name: [ nil, "" ]).distinct.order(:project_name).pluck(:project_name)
    @selected_project = params[:project].presence_in(@project_options)
    @selected_month = params[:month].presence_in(MONTH_KEYS)
    @visible_months = visible_months_for(@selected_month)
    @prior_months = @visible_months[0...-1]
    @submitted_locked = selected_budget_scope.where(status: "submitted").exists?
    @has_draft = selected_budget_scope.where(status: "draft").exists?
    @selected_budget_status = if @submitted_locked
      "submitted"
    elsif @has_draft
      "draft"
    else
      "not_started"
    end
    @rows = if @selected_project.present? && @selected_month.present?
      budget_rows_for(@selected_project, @selected_month)
    else
      []
    end
    @project_total = @rows.sum { |row| row[:total_allocated].to_d }
    @month_total = @rows.sum { |row| row[:month_amount].to_d }
    @utilized_total = @rows.sum { |row| row[:utilized_amount].to_d }
    @expenditure_total = @rows.sum { |row| row[:total_expenditure].to_d }
    @remaining_total = @project_total - @expenditure_total
  end

  def activity_scope
    scope = BliActivity.with_single_bli_code
    return scope if @can_edit
    return scope.none if current_user.employee.blank?

    scope.where(employee_id: current_user.employee.id)
  end

  def visible_months_for(selected_month)
    return [] if selected_month.blank?

    index = MONTH_KEYS.index(selected_month)
    return [] unless index

    MONTH_KEYS[0..index]
  end

  def budget_rows_for(project_name, month)
    activities = activity_scope.where(project_name: project_name).order(:bli_code, :name, :activity_name, :vertical_name)
    months = visible_months_for(month)
    existing_scope = BudgetUtilization.with_single_bli_code.where(project_name: project_name, month: months)
    existing_scope = existing_scope.submitted unless @can_edit
    existing = existing_scope
      .group_by { |utilization| [ utilization.project_name, utilization.bli_code.to_s ] }

    activities
      .group_by { |activity| [ activity.project_name, activity.bli_code.to_s ] }
      .map do |(project, bli_code), grouped_activities|
        sample = grouped_activities.first
        total_allocated = grouped_activities.map { |activity| activity.allocated_fund.to_d }.max || 0
        project_bli_name = grouped_activities.map { |activity| activity.name.presence || activity.activity_name }.compact_blank.first
        vertical_name = sample.vertical_name
        month_amount = month_amount_for(total_allocated, vertical_name, month)
        by_month = (existing[[ project, bli_code ]] || []).index_by(&:month)

        month_utilized = months.index_with do |candidate|
          by_month[candidate]&.utilized_amount.to_d
        end
        current = by_month[month]
        prior_expenditure = months[0...-1].sum { |candidate| month_utilized[candidate].to_d }
        current_utilized = current&.utilized_amount.to_d
        total_expenditure = prior_expenditure + current_utilized

        {
          project_name: project,
          activity_name: project_bli_name,
          vertical_name: vertical_name,
          bli_code: bli_code,
          total_allocated: total_allocated,
          month_utilized: month_utilized,
          prior_expenditure: prior_expenditure,
          total_expenditure: total_expenditure,
          total_remaining: total_allocated - total_expenditure,
          month_amount: month_amount,
          utilized_amount: current_utilized
        }
      end
      .sort_by { |row| [ bli_code_sort_key(row[:bli_code]), row[:activity_name].to_s ] }
  end

  def bli_code_sort_key(code)
    code.to_s.split(".").map { |part| part.to_i }
  end

  def month_amount_for(total_amount, vertical_name, month)
    percent = VerticalPercent.find_by(vertical_name: vertical_name)
    if month == MONTH_KEYS.last
      earlier_months = MONTH_KEYS[0...-1].sum do |candidate|
        (total_amount * (percent&.public_send(candidate) || 0) / 100).round(2)
      end
      total_amount - earlier_months
    else
      (total_amount * (percent&.public_send(month) || 0) / 100).round(2)
    end
  end

  def decimal(value)
    BigDecimal(value.to_s.presence || "0")
  rescue ArgumentError
    0
  end

  def selected_budget_scope
    return BudgetUtilization.none if @selected_project.blank? || @selected_month.blank?

    BudgetUtilization.with_single_bli_code.where(project_name: @selected_project, month: @selected_month)
  end
end

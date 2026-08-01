class ProjectSummariesController < ApplicationController
  ALL_PROJECTS_OPTION = "__all_projects__".freeze

  before_action :require_login
  before_action :redirect_admin

  def index
    @employee = current_user.employee
    @project_options = @employee.projects
    @selected_project = selected_project_param
    @all_projects_selected = @selected_project == ALL_PROJECTS_OPTION
    @activities = scoped_activities
    @existing_summary_submission = existing_summary_submission
    @summary_rows = build_summary_rows
    @grand_total = @summary_rows.sum { |row| row[:total_amount] }
  end

  def create
    ProjectSummarySubmission.reset_column_information
    ProjectSummarySubmissionItem.reset_column_information

    employee = current_user.employee
    rows = summary_params
    selected_project = params[:project_name].to_s.presence
    total_amount = rows.sum { |row| decimal(row[:total_amount]) }

    approved_submission = employee.project_summary_submissions
      .joins(:project_summary_submission_items)
      .where(status: "approved", project_summary_submission_items: { project_name: submission_project_names(selected_project, rows) })
      .distinct
      .first

    if approved_submission
      redirect_to project_summary_records_path, alert: "Approved project summary cannot be changed."
      return
    end

    submission = employee.project_summary_submissions
      .where.not(status: "approved")
      .joins(:project_summary_submission_items)
      .where(project_summary_submission_items: { project_name: submission_project_names(selected_project, rows) })
      .order(submitted_at: :desc)
      .first_or_initialize

    ProjectSummarySubmission.transaction do
      submission.assign_attributes(
        approver: ProjectSummarySubmission.approver_employee,
        submission_remark: params[:submission_remark].to_s.strip,
        total_amount: total_amount,
        status: "pending",
        reviewed_at: nil,
        submitted_at: Time.current
      )

      submission.project_summary_submission_items.destroy_all if submission.persisted?

      rows.each do |row|
        month_values = VerticalPercent::MONTH_COLUMNS.index_with { |month| decimal(row[month]) }
        changed_total = month_values.values.sum

        submission.project_summary_submission_items.build(
          activity_name: row[:activity_name],
          vertical_name: row[:vertical_name],
          project_name: row[:project_name],
          total_amount: decimal(row[:total_amount]),
          changed_total: changed_total,
          remark: row[:remark],
          **month_values
        )
      end

      submission.save!
    end

    redirect_to project_summary_records_path, notice: "Project summary sent for approval."
  rescue ArgumentError
    redirect_to project_summary_path, alert: "Invalid monthly amount value."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_summary_path, alert: error.record.errors.full_messages.to_sentence.presence || "Every row changed total must match its total amount."
  end

  private

  def redirect_admin
    return redirect_to admin_employees_path if current_user.admin?

    redirect_to project_summary_records_path if ProjectSummarySubmission.summary_access?(current_user.employee)
  end

  def scoped_activities
    return @employee.bli_activities.none if @selected_project.blank?
    return @employee.accessible_bli_activities if @all_projects_selected

    @employee.accessible_bli_activities.select { |activity| activity.project_name == @selected_project }
  end

  def selected_project_param
    project = params[:project].to_s
    return ALL_PROJECTS_OPTION if project == ALL_PROJECTS_OPTION

    project.presence_in(@project_options)
  end

  def selected_project_title
    @all_projects_selected ? "All Project" : @selected_project
  end
  helper_method :selected_project_title

  def summary_params
    params.fetch(:summary, {}).values.map do |row|
      row.permit(:activity_name, :vertical_name, :project_name, :total_amount, :remark, *VerticalPercent::MONTH_COLUMNS)
    end
  end

  def decimal(value)
    BigDecimal(value.presence || "0")
  end

  def existing_summary_submission
    return if @selected_project.blank?
    return all_projects_summary_submission if @all_projects_selected

    @employee.project_summary_submissions
      .joins(:project_summary_submission_items)
      .where(project_summary_submission_items: { project_name: @selected_project })
      .includes(:project_summary_submission_items)
      .order(submitted_at: :desc)
      .distinct
      .first
  end

  def all_projects_summary_submission
    @employee.project_summary_submissions
      .joins(:project_summary_submission_items)
      .where(project_summary_submission_items: { project_name: @project_options })
      .includes(:project_summary_submission_items)
      .order(submitted_at: :desc)
      .distinct
      .first
  end

  def submission_project_names(selected_project, rows)
    selected_project == ALL_PROJECTS_OPTION ? rows.map { |row| row[:project_name] }.compact_blank.uniq : selected_project
  end

  def build_summary_rows
    saved_items_by_key = (@existing_summary_submission&.project_summary_submission_items || []).index_by do |item|
      [ item.project_name, item.activity_name, item.vertical_name ]
    end

    @activities
      .group_by { |activity| [ activity.project_name, activity.activity_name, activity.vertical_name ] }
      .transform_values { |activities| activities.sum(&:allocated_fund) }
      .map do |(project_name, activity_name, vertical_name), total_amount|
        percent = VerticalPercent.find_by(vertical_name: vertical_name)
        saved_item = saved_items_by_key[[ project_name, activity_name, vertical_name ]]
        month_amounts = if saved_item
          VerticalPercent::MONTH_COLUMNS.index_with { |month| saved_item.public_send(month) }
        else
          month_amounts_for(total_amount, percent)
        end

        {
          project_name: project_name,
          activity_name: activity_name,
          vertical_name: vertical_name,
          total_amount: total_amount,
          percent: percent,
          month_amounts: month_amounts,
          remark: saved_item&.remark
        }
      end
      .sort_by { |row| [ row[:project_name].to_s, -row[:total_amount], row[:activity_name].to_s ] }
  end

  def month_amounts_for(total_amount, percent)
    amounts = {}
    running_total = BigDecimal("0")

    VerticalPercent::MONTH_COLUMNS.each_with_index do |month, index|
      monthly_percent = percent&.public_send(month) || 0
      amount = if index == VerticalPercent::MONTH_COLUMNS.size - 1
        total_amount - running_total
      else
        (total_amount * monthly_percent / 100).round(2)
      end

      amounts[month] = amount
      running_total += amount
    end

    amounts
  end
end

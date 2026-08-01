class ProjectSummaryRecordsController < ApplicationController
  before_action :require_login
  before_action :set_editable_submission, only: :update

  def index
    ProjectSummarySubmissionItem.reset_column_information

    @submissions = submission_scope
      .includes(:employee, :project_summary_submission_items)
      .order(submitted_at: :desc)
    @all_record_groups = build_record_groups
    @vertical_options = vertical_options_for(@all_record_groups)
    @show_vertical_filter = privileged_record_view?
    @selected_vertical = selected_vertical_for_records
    @selected_verticals = selected_verticals_for_records
    @summary_vertical_label = summary_vertical_label
    @record_groups = @selected_verticals.any? ? filter_record_groups_by_verticals(@all_record_groups, @selected_verticals) : []
    @status_records = status_records_for(@record_groups)
    @total_records = @record_groups.size
    @overall_summary = overall_record_summary(@record_groups)
    @activity_summaries = activity_summaries_for(@record_groups)
  end

  def update
    ProjectSummarySubmissionItem.reset_column_information

    ProjectSummarySubmission.transaction do
      @submission.update!(
        approver: ProjectSummarySubmission.approver_employee,
        submission_remark: params[:submission_remark].to_s.strip,
        status: "pending",
        reviewed_at: nil,
        submitted_at: Time.current
      )

      record_items_params.each do |item_id, row|
        item = @submission.project_summary_submission_items.find(item_id)
        month_values = VerticalPercent::MONTH_COLUMNS.index_with { |month| decimal(row[month.to_s]) }

        item.update!(
          changed_total: month_values.values.sum,
          remark: row["remark"],
          **month_values
        )
      end
    end

    redirect_to project_summary_records_path(vertical: params[:vertical].presence), notice: "Project summary sent for approval."
  rescue ArgumentError
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: "Invalid monthly amount value."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: error.record.errors.full_messages.to_sentence.presence || "Every row changed total must match its total amount."
  end

  def bulk_update
    ProjectSummarySubmissionItem.reset_column_information

    ProjectSummarySubmission.transaction do
      bulk_record_params.each_value do |record|
        employee = current_user.employee
        project_name = record["project_name"].to_s
        rows = record.fetch("rows", {}).values
        next if project_name.blank? || rows.blank?

        submission = editable_submission_for(employee, project_name)
        next if submission.approved?

        total_amount = rows.sum { |row| decimal(row["total_amount"]) }

        submission.assign_attributes(
          approver: ProjectSummarySubmission.approver_employee,
          submission_remark: record["submission_remark"].to_s.strip,
          total_amount: total_amount,
          status: "pending",
          reviewed_at: nil,
          submitted_at: Time.current
        )

        submission.project_summary_submission_items.destroy_all if submission.persisted?

        rows.each do |row|
          month_values = VerticalPercent::MONTH_COLUMNS.index_with { |month| decimal(row[month.to_s]) }

          submission.project_summary_submission_items.build(
            project_name: row["project_name"].presence || project_name,
            activity_name: row["activity_name"],
            vertical_name: row["vertical_name"],
            total_amount: decimal(row["total_amount"]),
            changed_total: month_values.values.sum,
            remark: row["remark"],
            **month_values
          )
        end

        submission.save!
      end
    end

    redirect_to project_summary_records_path(vertical: params[:vertical].presence), notice: "Project summaries sent for approval."
  rescue ArgumentError
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: "Invalid monthly amount value."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: error.record.errors.full_messages.to_sentence.presence || "Every row changed total must match its total amount."
  end

  private

  def set_editable_submission
    @submission = current_user.employee.project_summary_submissions.find(params[:id])
    return unless @submission.approved?

    redirect_to project_summary_records_path, alert: "Approved project summary cannot be changed."
  end

  def record_items_params
    params.fetch(:summary, {}).permit!.to_h
  end

  def bulk_record_params
    params.fetch(:records, {}).permit!.to_h
  end

  def decimal(value)
    BigDecimal(value.presence || "0")
  end

  def submission_scope
    if current_user.admin?
      ProjectSummarySubmission.all
    elsif ProjectSummarySubmission.summary_approver?(current_user.employee)
      ProjectSummarySubmission.where("employee_id = :employee_id OR approver_id = :employee_id", employee_id: current_user.employee.id)
    elsif ProjectSummarySubmission.summary_viewer?(current_user.employee)
      ProjectSummarySubmission.all
    else
      current_user.employee.project_summary_submissions
    end
  end

  def build_record_groups
    baseline_employees.flat_map do |employee|
      projects = employee.projects
        submissions_by_project = employee.project_summary_submissions
          .includes(:project_summary_submission_items)
          .order(submitted_at: :desc)
          .each_with_object({}) do |submission, latest|
          submission.project_summary_submission_items.map(&:project_name).compact_blank.uniq.each do |project_name|
            latest[project_name] ||= submission
          end
        end

      projects.map do |project_name|
        submission = submissions_by_project[project_name]
        rows = submission ? rows_from_submission(submission, project_name) : calculated_summary_rows(employee, project_name)
        editable = if submission
          submission.editable_by?(current_user)
        else
          current_user.employee_id == employee.id
        end

        {
          form_key: "#{employee.id}-#{project_name}".parameterize,
          project_name: project_name,
          employee: employee,
          submission: submission,
          status: submission&.status || "not_submitted",
          status_label: submission&.status_label || "Not Submitted",
          submitted_at: submission&.submitted_at,
          reviewed_at: submission&.reviewed_at,
          approver: submission&.approver || ProjectSummarySubmission.approver_employee,
          editable: editable,
          rows: rows,
          change_summary: change_summary_for(rows),
          month_totals: month_totals_for(rows),
          planned_month_totals: planned_month_totals_for(rows),
          submission_remark: submission&.submission_remark,
          approval_remark: submission&.approval_remark,
          total_amount: rows.sum { |row| row[:total_amount] }
        }
      end
    end
  end

  def vertical_options_for(record_groups)
    record_groups
      .flat_map { |record| record[:rows].map { |row| row[:vertical_name].presence || "Unassigned Vertical" } }
      .uniq
      .sort
  end

  def selected_vertical_for_records
    selected = params[:vertical].to_s.presence_in(@vertical_options)
    return selected if @show_vertical_filter && selected.present?

    nil
  end

  def selected_verticals_for_records
    return [ @selected_vertical ] if @show_vertical_filter && @selected_vertical.present?
    return @vertical_options if @show_vertical_filter

    own_verticals = current_user.employee.verticals & @vertical_options
    own_verticals.presence || @vertical_options
  end

  def summary_vertical_label
    return @selected_vertical.presence || "All Verticals" if @show_vertical_filter

    @selected_verticals.join(" + ")
  end

  def filter_record_groups_by_verticals(record_groups, vertical_names)
    record_groups.filter_map do |record|
      rows = record[:rows].select { |row| vertical_names.include?(row[:vertical_name].presence || "Unassigned Vertical") }
      next if rows.blank?

      record.merge(
        rows: rows,
        change_summary: change_summary_for(rows),
        month_totals: month_totals_for(rows),
        planned_month_totals: planned_month_totals_for(rows),
        total_amount: rows.sum { |row| row[:total_amount] }
      )
    end
  end

  def status_records_for(record_groups)
    record_groups
      .select { |record| record[:submission].present? }
      .uniq { |record| status_record_key(record) }
  end

  def status_record_key(record)
    [
      record[:status],
      record[:approver]&.id,
      record[:submitted_at]&.strftime("%d %b %Y, %I:%M %p"),
      record[:reviewed_at]&.strftime("%d %b %Y, %I:%M %p"),
      record[:approval_remark].to_s,
      record[:submission_remark].to_s
    ]
  end

  def baseline_employees
    return privileged_baseline_employees if privileged_record_view?
    return [ current_user.employee ] if current_user.employee.accessible_bli_activities.any?

    Employee.where(active: true).joins(:bli_activities).distinct.order(:name)
  end

  def privileged_baseline_employees
    Employee.where(active: true).joins(:bli_activities).distinct.order(:name)
  end

  def privileged_record_view?
    current_user.admin? || ProjectSummarySubmission.summary_access?(current_user.employee)
  end

  def rows_from_submission(submission, project_name = nil)
    items = submission.project_summary_submission_items
    items = items.select { |item| item.project_name == project_name } if project_name.present?
    bli_code_lookup = bli_code_lookup_for(submission.employee)

    items.map do |item|
      planned_month_amounts = planned_month_amounts_for(item.total_amount, item.vertical_name)
      month_amounts = VerticalPercent::MONTH_COLUMNS.index_with { |month| item.public_send(month) }

      {
        item: item,
        project_name: item.project_name,
        activity_name: item.activity_name,
        vertical_name: item.vertical_name,
        bli_code: bli_code_lookup[[ item.project_name, item.activity_name, item.vertical_name ]],
        total_amount: item.total_amount,
        month_amounts: month_amounts,
        planned_month_amounts: planned_month_amounts,
        month_deltas: month_deltas_for(month_amounts, planned_month_amounts),
        changed_total: item.changed_total,
        remark: item.remark
      }
    end
  end

  def calculated_summary_rows(employee, project_name)
    employee.accessible_bli_activities
      .select { |activity| activity.project_name == project_name }
      .group_by { |activity| [ activity.project_name, activity.activity_name, activity.vertical_name ] }
      .map do |(row_project_name, activity_name, vertical_name), activities|
        total_amount = activities.sum(&:allocated_fund)
        bli_codes = activities.map(&:bli_code).compact_blank.uniq
        percent = VerticalPercent.find_by(vertical_name: vertical_name)
        month_amounts = month_amounts_for(total_amount, percent)

        {
          item: nil,
          project_name: row_project_name,
          activity_name: activity_name,
          vertical_name: vertical_name,
          bli_code: bli_codes.one? ? bli_codes.first : bli_codes.join(", "),
          total_amount: total_amount,
          month_amounts: month_amounts,
          planned_month_amounts: month_amounts,
          month_deltas: month_deltas_for(month_amounts, month_amounts),
          changed_total: month_amounts.values.sum,
          remark: nil
        }
      end
      .sort_by { |row| [ -row[:total_amount], row[:activity_name].to_s ] }
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

  def planned_month_amounts_for(total_amount, vertical_name)
    month_amounts_for(total_amount, VerticalPercent.find_by(vertical_name: vertical_name))
  end

  def month_deltas_for(month_amounts, planned_month_amounts)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      month_amounts[month].to_d - planned_month_amounts[month].to_d
    end
  end

  def change_summary_for(rows)
    changed_rows = rows.filter_map do |row|
      changed_months = row[:month_deltas].select { |_month, delta| delta.abs >= 0.01 }
      next if changed_months.blank?

      {
        activity_name: row[:activity_name],
        vertical_name: row[:vertical_name],
        changed_months: changed_months,
        remark: row[:remark]
      }
    end

    {
      changed_rows: changed_rows,
      changed_row_count: changed_rows.size,
      changed_month_count: changed_rows.sum { |row| row[:changed_months].size }
    }
  end

  def month_totals_for(rows)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      rows.sum { |row| row[:month_amounts][month].to_d }
    end
  end

  def planned_month_totals_for(rows)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      rows.sum { |row| row[:planned_month_amounts][month].to_d }
    end
  end

  def overall_record_summary(record_groups)
    status_counts = record_groups.each_with_object(Hash.new(0)) do |record, counts|
      counts[record[:status]] += 1
    end

    {
      total_projects: record_groups.size,
      total_rows: record_groups.sum { |record| record[:rows].size },
      total_amount: record_groups.sum { |record| record[:total_amount].to_d },
      changed_projects: record_groups.count { |record| record[:change_summary][:changed_row_count].positive? },
      changed_rows: record_groups.sum { |record| record[:change_summary][:changed_row_count] },
      changed_months: record_groups.sum { |record| record[:change_summary][:changed_month_count] },
      status_counts: status_counts,
      month_totals: VerticalPercent::MONTH_COLUMNS.index_with do |month|
        record_groups.sum { |record| record[:month_totals][month].to_d }
      end
    }
  end

  def activity_summaries_for(record_groups)
    rows = record_groups.flat_map { |record| record[:rows] }

    rows
      .group_by { |row| row[:activity_name].presence || "Unassigned Activity" }
      .map do |activity_name, activity_rows|
        project_breakdown = activity_rows
          .group_by { |row| row[:project_name].presence || "Unassigned Project" }
          .map do |project_name, project_rows|
            {
              project_name: project_name,
              total_amount: project_rows.sum { |row| row[:total_amount].to_d },
              month_totals: month_totals_for(project_rows),
              planned_month_totals: planned_month_totals_for(project_rows)
            }
          end
          .select { |project| project[:total_amount].positive? }
          .sort_by { |project| [ -project[:total_amount], project[:project_name].to_s ] }

        bli_codes = activity_rows.flat_map { |row| row[:bli_code].to_s.split(", ") }.compact_blank.uniq

        {
          activity_name: activity_name,
          bli_code: bli_codes.one? ? bli_codes.first : (bli_codes.any? ? bli_codes.join(", ") : "-"),
          project_count: project_breakdown.size,
          total_amount: activity_rows.sum { |row| row[:total_amount].to_d },
          month_totals: month_totals_for(activity_rows),
          planned_month_totals: planned_month_totals_for(activity_rows),
          projects: project_breakdown
        }
      end
      .sort_by { |activity| [ -activity[:total_amount], activity[:activity_name].to_s ] }
  end

  def bli_code_lookup_for(employee)
    employee.accessible_bli_activities.each_with_object({}) do |activity, lookup|
      key = [ activity.project_name, activity.activity_name, activity.vertical_name ]
      lookup[key] ||= activity.bli_code
    end
  end

  def editable_submission_for(employee, project_name)
    approved_submission = employee.project_summary_submissions
      .joins(:project_summary_submission_items)
      .where(status: "approved", project_summary_submission_items: { project_name: project_name })
      .distinct
      .first
    return approved_submission if approved_submission

    employee.project_summary_submissions
      .where.not(status: "approved")
      .joins(:project_summary_submission_items)
      .where(project_summary_submission_items: { project_name: project_name })
      .order(submitted_at: :desc)
      .distinct
      .first_or_initialize
  end
end

require "csv"

class ProjectSummaryRecordsController < ApplicationController
  before_action :require_login
  before_action :require_employee_budget_edit_access, only: %i[update bulk_update]
  before_action :set_editable_submission, only: :update

  SOURCE_EXPORT_HEADERS = [
    "Project ID",
    "Project Name",
    "Office Name",
    "Project Bli Code",
    "Project_Bli_Name",
    "Bli Allocated Fund",
    "ASA Theme ID",
    "ASA Theme",
    "ASA Activity ID",
    "ASA Activity",
    "Responsible Users"
  ].freeze

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
    @overall_summary = overall_record_summary(@record_groups)
    @total_records = @overall_summary[:total_projects]
    @activity_summaries = activity_summaries_for(@record_groups)

    respond_to do |format|
      format.html
      format.csv do
        send_data project_summary_records_csv,
          filename: "project_summary_records_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(project_summary_records_csv, title: "Project Summary Records", sheet_name: "Summary Records"),
          filename: "project_summary_records_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
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
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: "Every row changed total must match its total amount."
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
        ensure_changed_totals_match!(rows)

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
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: "Every row changed total must match its total amount."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: error.record.errors.full_messages.to_sentence.presence || "Every row changed total must match its total amount."
  end

  private

  def set_editable_submission
    @submission = current_user.employee.project_summary_submissions.find(params[:id])
    return unless @submission.approved?

    redirect_to project_summary_records_path, alert: "Approved project summary cannot be changed."
  end

  def require_employee_budget_edit_access
    return if current_user.employee.present? && !current_user.admin? && !ProjectSummarySubmission.summary_access?(current_user.employee)

    redirect_to project_summary_records_path(vertical: params[:vertical].presence), alert: "MIS can view records but cannot edit."
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

  def ensure_changed_totals_match!(rows)
    rows.each do |row|
      total_amount = decimal(row["total_amount"])
      changed_total = VerticalPercent::MONTH_COLUMNS.sum { |month| decimal(row[month.to_s]) }
      next if (changed_total - total_amount).abs < BigDecimal("0.01")

      raise ArgumentError, "changed total mismatch"
    end
  end

  def submission_scope
    if current_user.admin?
      ProjectSummarySubmission.all
    elsif ProjectSummarySubmission.summary_approver?(current_user.employee)
      ProjectSummarySubmission.where("employee_id = :employee_id OR approver_id = :employee_id", employee_id: current_user.employee.id)
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
        editable = record_group_editable?(employee, submission)
        detailed_rows = detailed_record_rows? && !editable
        rows = if submission
          rows_from_submission(submission, project_name, detailed: detailed_rows)
        else
          calculated_summary_rows(employee, project_name, detailed: detailed_rows)
        end

        {
          form_key: "#{employee.id}-#{project_name}".parameterize,
          project_name: project_name,
          employee: employee,
          submission: submission,
          status: submission&.status || "not_submitted",
          status_label: submission ? helpers.summary_approval_status_label(submission) : "Not Submitted",
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

  def baseline_employees
    return employees_with_active_pb_rows if privileged_record_view?
    return [ current_user.employee ] if current_user.employee.accessible_bli_activities.any?

    employees_with_active_pb_rows
  end

  def employees_with_active_pb_rows
    Employee
      .joins(:bli_activities)
      .merge(BliActivity.active)
      .distinct
      .order(:name)
  end

  def privileged_record_view?
    current_user.admin? || ProjectSummarySubmission.summary_access?(current_user.employee)
  end

  def record_group_editable?(employee, submission)
    return false if privileged_record_view?

    if submission
      submission.editable_by?(current_user)
    else
      current_user.employee_id == employee.id
    end
  end

  def detailed_record_rows?
    privileged_record_view?
  end

  def rows_from_submission(submission, project_name = nil, detailed: false)
    current_rows = calculated_summary_rows(submission.employee, project_name, detailed: detailed)
    saved_items_by_key = submission_items_for(submission, project_name).group_by { |item| submission_item_key(item) }

    return submitted_rows_without_current_pb(submission, project_name) if current_rows.blank?
    return merge_submission_items_into_detailed_rows(current_rows, saved_items_by_key) if detailed

    current_rows.map do |row|
      items = saved_items_by_key[row_submission_key(row)]
      next row if items.blank?

      month_amounts = align_month_amounts_to_total(
        combined_submission_month_amounts(items),
        row[:total_amount]
      )

      row.merge(
        item: items.first,
        month_amounts: month_amounts,
        month_deltas: month_deltas_for(month_amounts, row[:planned_month_amounts]),
        changed_total: month_amounts.values.sum,
        remark: first_submission_remark(items)
      )
    end
  end

  def submitted_rows_without_current_pb(submission, project_name = nil)
    bli_code_lookup = bli_code_lookup_for(submission.employee)

    submission_items_for(submission, project_name).map do |item|
      planned_month_amounts = planned_month_amounts_for(item.total_amount, item.vertical_name)
      month_amounts = VerticalPercent::MONTH_COLUMNS.index_with { |month| item.public_send(month) }

      {
        item: item,
        project_name: item.project_name,
        activity_name: item.activity_name,
        vertical_name: item.vertical_name,
        bli_code: bli_code_lookup[[ item.project_name, item.activity_name, item.vertical_name ]],
        activity_count: 1,
        total_amount: item.total_amount,
        bli_allocated_fund: item.total_amount,
        month_amounts: month_amounts,
        planned_month_amounts: planned_month_amounts,
        month_deltas: month_deltas_for(month_amounts, planned_month_amounts),
        changed_total: item.changed_total,
        remark: item.remark
      }
    end
  end

  def submission_items_for(submission, project_name = nil)
    items = submission.project_summary_submission_items
    items = items.select { |item| item.project_name == project_name } if project_name.present?
    items
  end

  def calculated_summary_rows(employee, project_name, detailed: false)
    activities = employee.accessible_bli_activities.select { |activity| activity.project_name == project_name }
    return calculated_activity_rows(activities) if detailed

    calculated_grouped_summary_rows(activities)
  end

  def calculated_activity_rows(activities)
    sort_summary_rows(
      activities.map do |activity|
        total_amount = activity.allocated_fund.to_d
        percent = vertical_percent_for(activity.vertical_name)
        month_amounts = month_amounts_for(total_amount, percent)

        {
          item: nil,
          source_bli_activity: activity,
          source_activity_id: activity.id,
          project_name: activity.project_name,
          office_name: activity.office_name,
          activity_name: activity.activity_name,
          vertical_name: activity.vertical_name,
          bli_code: activity.bli_code,
          project_bli_name: activity.name,
          responsible_user_name: activity.responsible_user_name,
          bli_allocated_fund: activity.allocated_fund,
          activity_count: 1,
          total_amount: total_amount,
          month_amounts: month_amounts,
          planned_month_amounts: month_amounts,
          month_deltas: month_deltas_for(month_amounts, month_amounts),
          changed_total: month_amounts.values.sum,
          remark: nil
        }
      end
    )
  end

  def calculated_grouped_summary_rows(activities)
    activities
      .group_by { |activity| [ activity.project_name, activity.activity_name, activity.vertical_name ] }
      .map do |(row_project_name, activity_name, vertical_name), activities|
        total_amount = activities.sum { |activity| activity.allocated_fund.to_d }
        bli_codes = activities.map(&:bli_code).compact_blank.uniq
        percent = vertical_percent_for(vertical_name)
        month_amounts = month_amounts_for(total_amount, percent)

        {
          item: nil,
          source_bli_activity: activities.first,
          project_name: row_project_name,
          office_name: aggregate_label(activities.map(&:office_name)),
          activity_name: activity_name,
          vertical_name: vertical_name,
          bli_code: bli_codes.one? ? bli_codes.first : bli_codes.join(", "),
          project_bli_name: aggregate_label(activities.map(&:name)),
          responsible_user_name: aggregate_label(activities.map(&:responsible_user_name)),
          bli_allocated_fund: total_amount,
          activity_count: activities.size,
          total_amount: total_amount,
          month_amounts: month_amounts,
          planned_month_amounts: month_amounts,
          month_deltas: month_deltas_for(month_amounts, month_amounts),
          changed_total: month_amounts.values.sum,
          remark: nil
        }
      end
      .then { |rows| sort_summary_rows(rows) }
  end

  def merge_submission_items_into_detailed_rows(current_rows, saved_items_by_key)
    current_rows
      .group_by { |row| row_submission_key(row) }
      .values
      .flat_map do |activity_rows|
        items = saved_items_by_key[row_submission_key(activity_rows.first)]
        next activity_rows if items.blank?

        group_total = activity_rows.sum { |row| row[:total_amount].to_d }
        group_month_amounts = align_month_amounts_to_total(
          combined_submission_month_amounts(items),
          group_total
        )

        activity_rows.map do |row|
          month_amounts = proportional_month_amounts(group_month_amounts, row[:total_amount].to_d, group_total)

          row.merge(
            item: items.first,
            month_amounts: month_amounts,
            month_deltas: month_deltas_for(month_amounts, row[:planned_month_amounts]),
            changed_total: month_amounts.values.sum,
            remark: first_submission_remark(items)
          )
        end
      end
  end

  def submission_item_key(item)
    [ item.project_name, item.activity_name, item.vertical_name ]
  end

  def row_submission_key(row)
    [ row[:project_name], row[:activity_name], row[:vertical_name] ]
  end

  def combined_submission_month_amounts(items)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      items.sum { |item| item.public_send(month).to_d }
    end
  end

  def first_submission_remark(items)
    items.map(&:remark).compact_blank.first
  end

  def proportional_month_amounts(month_amounts, row_total, group_total)
    zero_amounts = VerticalPercent::MONTH_COLUMNS.index_with { BigDecimal("0") }
    return zero_amounts if group_total.zero?

    scaled = VerticalPercent::MONTH_COLUMNS.index_with do |month|
      (month_amounts[month].to_d * row_total / group_total).round(2)
    end

    align_month_amounts_to_total(scaled, row_total)
  end

  def sort_summary_rows(rows)
    rows.sort_by do |row|
      [
        -row[:total_amount].to_d,
        row[:activity_name].to_s,
        row[:bli_code].to_s,
        row[:source_activity_id].to_i
      ]
    end
  end

  def aggregate_label(values)
    labels = values.compact_blank.uniq
    labels.one? ? labels.first : labels.join(", ")
  end

  def vertical_percent_for(vertical_name)
    @vertical_percent_cache ||= {}
    key = vertical_name.to_s
    @vertical_percent_cache.fetch(key) do
      @vertical_percent_cache[key] = VerticalPercent.find_by(vertical_name: vertical_name)
    end
  end

  def align_month_amounts_to_total(month_amounts, total_amount)
    amounts = month_amounts.transform_values(&:to_d)
    delta = total_amount.to_d - amounts.values.sum
    return amounts if delta.abs < BigDecimal("0.01")

    last_month = VerticalPercent::MONTH_COLUMNS.last
    amounts[last_month] = amounts[last_month].to_d + delta
    amounts
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
    month_amounts_for(total_amount, vertical_percent_for(vertical_name))
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
      total_projects: unique_project_count_for(record_groups),
      total_record_groups: record_groups.size,
      total_verticals: unique_vertical_count_for(record_groups),
      total_rows: record_groups.sum { |record| record[:rows].size },
      total_activity_rows: record_groups.sum { |record| record[:rows].sum { |row| summary_activity_count(row) } },
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

  def unique_project_count_for(record_groups)
    record_groups
      .map { |record| record[:project_name].presence }
      .compact
      .uniq
      .size
  end

  def unique_vertical_count_for(record_groups)
    record_groups
      .flat_map { |record| record[:rows].map { |row| row[:vertical_name].presence || "Unassigned Vertical" } }
      .uniq
      .size
  end

  def summary_activity_count(row)
    count = row[:activity_count].to_i
    count.positive? ? count : 1
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

  def project_summary_records_csv
    CSV.generate(headers: true) do |csv|
      csv << [
        *SOURCE_EXPORT_HEADERS,
        "Project",
        "Employee",
        "Status",
        "Submitted At",
        "Project BLI Code",
        "P&B Activity Count",
        "ASA Activity",
        "Project P&B",
        "Total Amount",
        *VerticalPercent::MONTH_COLUMNS.map { |month| month.to_s.titleize },
        "Changed Total",
        "Remark"
      ]

      @record_groups.each do |record|
        record[:rows].each do |row|
          metadata = export_metadata_for(row)

          csv << [
            metadata[:project_id],
            row[:project_name],
            metadata[:office_name],
            metadata[:project_bli_code],
            metadata[:project_bli_name],
            metadata[:bli_allocated_fund],
            metadata[:asa_theme_id],
            metadata[:asa_theme],
            metadata[:asa_activity_id],
            metadata[:asa_activity],
            metadata[:responsible_user_name],
            record[:project_name],
            record[:employee].name,
            record[:status_label],
            helpers.format_record_datetime(record[:submitted_at]),
            metadata[:project_bli_code],
            summary_activity_count(row),
            metadata[:asa_activity],
            row[:vertical_name],
            row[:total_amount],
            *VerticalPercent::MONTH_COLUMNS.map { |month| row[:month_amounts][month] },
            row[:changed_total],
            row[:remark]
          ]
        end
      end
    end
  end

  def export_metadata_for(row)
    activity = row[:source_bli_activity] || source_activity_for(row[:project_name], row[:activity_name], row[:vertical_name])
    action_plan_details = action_plan_details_for(row)

    {
      project_id: project_id_for(row[:project_name]),
      office_name: row[:office_name].presence || activity&.office_name,
      project_bli_code: row[:bli_code].presence || activity&.bli_code,
      project_bli_name: row[:project_bli_name].presence || activity&.name,
      bli_allocated_fund: row[:bli_allocated_fund].presence || activity&.allocated_fund || row[:total_amount],
      asa_theme_id: action_plan_details[:asa_theme_id],
      asa_theme: action_plan_details[:asa_theme],
      asa_activity_id: action_plan_details[:asa_activity_id],
      asa_activity: action_plan_details[:asa_activity],
      responsible_user_name: row[:responsible_user_name].presence || activity&.responsible_user_name
    }
  end

  def source_activity_for(project_name, activity_name, vertical_name)
    source_activity_cache.fetch([ project_name.to_s, activity_name.to_s, vertical_name.to_s ]) do |key|
      source_activity_cache[key] = BliActivity.active.find_by(
        project_name: project_name,
        activity_name: activity_name,
        vertical_name: vertical_name
      )
    end
  end

  def source_activity_cache
    @source_activity_cache ||= {}
  end

  def action_plan_details_for(row)
    activity_match, theme_match = action_plan_matches_for(row[:project_name], row[:activity_name], row[:vertical_name])

    {
      asa_theme_id: ActionPlanRow.format_decimal_string(theme_match&.asa_theme_id).presence,
      asa_theme: theme_match&.asa_theme.presence || row[:vertical_name],
      asa_activity_id: ActionPlanRow.format_decimal_string(activity_match&.asa_activity_id).presence,
      asa_activity: activity_match&.asa_activity_name.presence || row[:activity_name]
    }
  end

  def action_plan_matches_for(project_name, activity_name, vertical_name)
    activity_key = ActionPlanText.group_key(activity_name)
    vertical_key = ActionPlanText.group_key(vertical_name)
    rows = action_plan_rows_for_project(project_name)

    activity_match = rows.find do |row|
      activity_key.present? && [ row.asa_activity_name, row.activity ].any? { |value| ActionPlanText.group_key(value) == activity_key }
    end

    theme_match = activity_match || rows.find do |row|
      vertical_key.present? && [ row.asa_theme, row.theme ].any? { |value| ActionPlanText.group_key(value) == vertical_key }
    end

    [ activity_match, theme_match ]
  end

  def action_plan_rows_for_project(project_name)
    action_plan_rows_by_project.fetch(project_name.to_s) do |key|
      action_plan_rows_by_project[key] = ActionPlanRow.active_import
        .where(project_name: project_name)
        .select(:project_id, :asa_theme_id, :asa_theme, :asa_activity_id, :asa_activity_name, :theme, :activity)
        .order(:id)
        .to_a
    end
  end

  def action_plan_rows_by_project
    @action_plan_rows_by_project ||= {}
  end

  def project_id_for(project_name)
    normalized_name = project_name.to_s.squish
    return if normalized_name.blank?

    project_id_cache.fetch(normalized_name) do |key|
      project_id_cache[key] =
        ProjectInformationSheet
          .where("LOWER(project_title) = :project OR LOWER(project_id) = :project", project: key.downcase)
          .pick(:project_id) ||
        ActionPlanRow.active_import.where(project_name: key).where.not(project_id: [ nil, "" ]).pick(:project_id) ||
        ProjectOwnership.active.where(project_name: key).pick(:po_id)
    end
  end

  def project_id_cache
    @project_id_cache ||= {}
  end
end

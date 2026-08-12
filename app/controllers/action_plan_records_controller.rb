class ActionPlanRecordsController < ApplicationController
  include ActionPlanPresenter
  include ActionPlanSubmitting

  before_action :require_login
  before_action :require_employee_action_plan_edit_access, only: :create

  def index
    @project_options = record_project_options
    @selected_project = params[:project].to_s.presence_in(@project_options)
    @record_groups = build_record_groups
    @filtered_record_groups = @selected_project.present? ? @record_groups.select { |record| record[:project_name] == @selected_project } : @record_groups
    @overall_summary = overall_summary_for(@filtered_record_groups)
    @activity_summaries = activity_summaries_for(@filtered_record_groups)
  end

  def create
    project_names = Array(params[:project_names]).presence || [ params[:project_name] ]
    project_names = project_names.map(&:to_s).compact_blank.uniq
    allowed_projects = vertical_project_options

    unless current_user.employee.present? && project_names.present? && project_names.all? { |project_name| project_name.in?(allowed_projects) }
      redirect_to action_plan_records_path, alert: "Choose a valid vertical action plan record."
      return
    end

    submissions = []
    ActionPlanSubmission.transaction do
      project_names.each do |project_name|
        rows = action_plan_rows_for(project_name, vertical_filter: true)
        if rows.first&.po_id.blank?
          redirect_to action_plan_records_path(project: project_name), alert: "Please choose a valid project."
          raise ActiveRecord::Rollback
        end

        imbalance = unbalanced_rows_message(rows)
        if imbalance.present?
          redirect_to action_plan_records_path(project: project_name), alert: imbalance
          raise ActiveRecord::Rollback
        end

        submission = build_action_plan_submission(project_name: project_name, po_id: rows.first.po_id, plan_type: "vertical")
        submission.save!
        submissions << submission
      end
    end

    return if performed?

    redirect_to action_plan_records_path(project: params[:project].presence),
      notice: "#{submissions.size} vertical action plan #{"record".pluralize(submissions.size)} sent for Project Owner approval."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to action_plan_records_path(project: params[:project].presence), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def require_employee_action_plan_edit_access
    return if current_user.employee.present? && !current_user.admin?

    redirect_to action_plan_records_path(project: params[:project].presence || params[:project_name].presence), alert: "PMC can view records but cannot edit."
  end

  def record_project_options
    return all_project_options if current_user.admin?

    (vertical_project_options + submitted_vertical_project_options).compact_blank.uniq.sort
  end

  def submitted_vertical_project_options
    return [] if current_user.employee.blank?

    current_user.employee.action_plan_submissions.where(plan_type: "vertical").distinct.order(:project_name).pluck(:project_name)
  end

  def vertical_record_project?(project_name)
    current_user.employee.present? && project_name.in?(vertical_project_options)
  end

  def build_record_groups
    latest_submissions = latest_submissions_by_project

    @project_options.map do |project_name|
      submission = latest_submissions[project_name]
      rows = record_rows_for(project_name, submission)
      row_summaries = rows.map { |row| record_row_for(row) }

      {
        project_name: project_name,
        plan_type_label: submission&.plan_type_label || default_record_plan_type_label(project_name),
        can_submit_for_approval: vertical_record_project?(project_name),
        po_id: rows.first&.po_id || submission&.po_id,
        project_id: rows.first&.project_id,
        employee: submission&.employee || current_user.employee,
        submission: submission,
        status: submission&.status || "not_submitted",
        status_label: submission ? helpers.action_plan_status_badge_label(submission) : "Not Submitted",
        submitted_at: submission&.submitted_at,
        rows: row_summaries,
        total_target: row_summaries.sum { |row| row[:monthly_total] },
        planned_total: row_summaries.sum { |row| row[:planned_total] },
        achievement_total: row_summaries.sum { |row| row[:achievement_total] },
        month_totals: month_totals_for(row_summaries, :month_amounts),
        achievement_month_totals: month_totals_for(row_summaries, :achievement_month_amounts),
        change_summary: change_summary_for(row_summaries),
        balanced: row_summaries.all? { |row| row[:variance].zero? }
      }
    end
  end

  def latest_submissions_by_project
    scope = if current_user.admin?
      ActionPlanSubmission.all
    else
      current_user.employee.action_plan_submissions
    end

    scope.order(submitted_at: :desc).each_with_object({}) do |submission, latest|
      latest[submission.project_name] ||= submission
    end
  end

  def record_rows_for(project_name, submission)
    return submission.scoped_action_plan_rows if submission&.vertical_plan?

    action_plan_rows_for(project_name, vertical_filter: vertical_filter_for_records?(project_name))
  end

  def default_record_plan_type_label(project_name)
    vertical_filter_for_records?(project_name) ? "Vertical Action Plan" : "Project Action Plan"
  end

  # A project owner sees every row of the project they own, so the vertical
  # filter only applies to projects reaching the viewer through their verticals.
  def vertical_filter_for_records?(project_name)
    return false if current_user.admin? || action_plan_vertical_names.blank?

    !owned_project_keys.include?(ProjectOwnership.normalize_project_key(project_name))
  end

  def owned_project_keys
    @owned_project_keys ||= owned_project_options.map { |name| ProjectOwnership.normalize_project_key(name) }.to_set
  end

  def record_row_for(row)
    month_amounts = ActionPlanRow::MONTH_COLUMNS.index_with { |month| row.public_send(month).to_i }
    original_month_amounts = ActionPlanRow::MONTH_COLUMNS.index_with { |month| original_month_value(row, month) }
    achievement_month_amounts = ActionPlanRow::MONTH_DISPLAY_PAIRS.index_with do |pair|
      row.public_send(pair[:achievement_column]).to_i
    end.transform_keys { |pair| pair[:target_column] }
    month_deltas = ActionPlanRow::MONTH_COLUMNS.index_with { |month| month_amounts[month] - original_month_amounts[month] }

    {
      row: row,
      project_id: row.project_id,
      project_name: row.project_name,
      theme_id: row.theme_id,
      theme: row.theme,
      activity_id: row.activity_id,
      activity: row.activity,
      asa_theme_id: row.asa_theme_id,
      asa_theme: row.asa_theme,
      asa_activity_id: row.asa_activity_id,
      asa_activity_name: row.asa_activity_name,
      unit_type: row.unit_type,
      planned_total: row.planned_total.to_i,
      monthly_total: row.monthly_total,
      changed_total: row.monthly_total,
      achievement_total: row.target_total,
      variance: row.target_variance,
      month_amounts: month_amounts,
      original_month_amounts: original_month_amounts,
      achievement_month_amounts: achievement_month_amounts,
      month_deltas: month_deltas
    }
  end

  def original_month_value(row, month)
    column = "original_#{month}"
    return row.public_send(column).to_i if row.respond_to?(column)

    row.public_send(month).to_i
  end

  def month_totals_for(rows, key)
    ActionPlanRow::MONTH_COLUMNS.index_with do |month|
      rows.sum { |row| row[key][month].to_i }
    end
  end

  def change_summary_for(rows)
    changed_rows = rows.filter_map do |row|
      changed_months = row[:month_deltas].select { |_month, delta| delta != 0 }
      next if changed_months.blank?

      {
        activity: row[:activity],
        theme: row[:theme],
        changed_months: changed_months
      }
    end

    {
      changed_rows: changed_rows,
      changed_row_count: changed_rows.size,
      changed_month_count: changed_rows.sum { |row| row[:changed_months].size }
    }
  end

  def overall_summary_for(record_groups)
    {
      total_projects: record_groups.size,
      total_rows: record_groups.sum { |record| record[:rows].size },
      planned_total: record_groups.sum { |record| record[:planned_total] },
      target_total: record_groups.sum { |record| record[:total_target] },
      achievement_total: record_groups.sum { |record| record[:achievement_total] },
      changed_projects: record_groups.count { |record| record[:change_summary][:changed_row_count].positive? },
      changed_rows: record_groups.sum { |record| record[:change_summary][:changed_row_count] },
      changed_months: record_groups.sum { |record| record[:change_summary][:changed_month_count] },
      month_totals: ActionPlanRow::MONTH_COLUMNS.index_with { |month| record_groups.sum { |record| record[:month_totals][month] } },
      month_deltas: ActionPlanRow::MONTH_COLUMNS.index_with do |month|
        record_groups.sum { |record| record[:rows].sum { |row| row[:month_deltas][month].to_i } }
      end
    }
  end

  def activity_summaries_for(record_groups)
    record_groups
      .flat_map { |record| record[:rows] }
      .group_by { |row| asa_activity_group_key(row) }
      .map do |_key, rows|
        {
          asa_activity_id: canonical_label(rows.map { |row| row[:asa_activity_id] }),
          activity: canonical_label(rows.map { |row| row[:asa_activity_name].presence || row[:activity] }) || "Unassigned Activity",
          asa_theme: canonical_label(rows.map { |row| row[:asa_theme] }),
          project_count: rows.map { |row| row[:project_name] }.compact.uniq.size,
          planned_total: rows.sum { |row| row[:planned_total] },
          target_total: rows.sum { |row| row[:monthly_total] },
          achievement_total: rows.sum { |row| row[:achievement_total] },
          changed_month_count: rows.sum { |row| row[:month_deltas].count { |_month, delta| delta != 0 } },
          month_totals: month_totals_for(rows, :month_amounts),
          month_deltas: ActionPlanRow::MONTH_COLUMNS.index_with { |month| rows.sum { |row| row[:month_deltas][month].to_i } }
        }
      end
      .sort_by { |row| [ -row[:target_total], row[:activity].to_s ] }
  end

  # Prefer ASA Activity ID so the overall summary matches Project Summary Records
  # (one vertical activity across projects), falling back to name when ID is blank.
  def asa_activity_group_key(row)
    ActionPlanText.group_key(row[:asa_activity_id]).presence ||
      ActionPlanText.group_key(row[:asa_activity_name]).presence ||
      ActionPlanText.group_key(row[:activity]).presence ||
      "unassigned activity"
  end

  # Source data spells the same label inconsistently, so the most frequently
  # used spelling wins, falling back to alphabetical order for a stable pick.
  def canonical_label(values)
    tally = values.compact_blank.tally
    return if tally.empty?

    tally.min_by { |label, count| [ -count, label ] }.first
  end
end

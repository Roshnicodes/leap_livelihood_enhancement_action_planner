module ProjectSummaryReviewPresenter
  extend ActiveSupport::Concern

  private

  def vertical_options_for(submissions)
    submissions
      .flat_map do |submission|
        submission.project_summary_submission_items.map { |item| item.vertical_name.presence || "Unassigned Vertical" }
      end
      .uniq
      .sort
  end

  def filter_submissions_by_vertical(submissions, vertical_name)
    submissions.select do |submission|
      submission.project_summary_submission_items.any? do |item|
        (item.vertical_name.presence || "Unassigned Vertical") == vertical_name
      end
    end
  end

  def filter_summary_rows_by_vertical(rows, vertical_name)
    rows.select { |row| (row[:vertical_name].presence || "Unassigned Vertical") == vertical_name }
  end

  def summary_rows_for(submissions)
    bli_code_lookup = bli_code_lookup_for(submissions)

    submissions.flat_map(&:project_summary_submission_items).map do |item|
      month_amounts = VerticalPercent::MONTH_COLUMNS.index_with { |month| item.public_send(month) }
      planned_month_amounts = planned_month_amounts_for(item.total_amount, item.vertical_name)

      {
        project_name: item.project_name,
        activity_name: item.activity_name,
        vertical_name: item.vertical_name,
        bli_code: bli_code_lookup[[ item.project_name, item.activity_name, item.vertical_name ]],
        total_amount: item.total_amount,
        changed_total: item.changed_total,
        remark: item.remark,
        employee_name: item.project_summary_submission.employee.name,
        submission: item.project_summary_submission,
        month_amounts: month_amounts,
        planned_month_amounts: planned_month_amounts,
        month_deltas: month_deltas_for(month_amounts, planned_month_amounts)
      }
    end
  end

  def project_record_groups_for(rows)
    rows
      .group_by { |row| row[:project_name].presence || "Unassigned Project" }
      .map do |project_name, project_rows|
        {
          project_name: project_name,
          employee_names: project_rows.map { |row| row[:employee_name] }.compact_blank.uniq.sort,
          rows: project_rows.sort_by { |row| [ row[:activity_name].to_s, row[:vertical_name].to_s ] },
          total_amount: project_rows.sum { |row| row[:total_amount].to_d },
          month_totals: month_totals_for(project_rows)
        }
      end
      .sort_by { |project| [ -project[:total_amount], project[:project_name].to_s ] }
  end

  def activity_summaries_for(rows)
    rows
      .group_by { |row| row[:activity_name].presence || "Unassigned Activity" }
      .map do |activity_name, activity_rows|
        projects = project_breakdown_for(activity_rows)
        bli_codes = activity_rows.flat_map { |row| row[:bli_code].to_s.split(", ") }.compact_blank.uniq

        {
          activity_name: activity_name,
          bli_code: bli_codes.one? ? bli_codes.first : (bli_codes.any? ? bli_codes.join(", ") : "-"),
          project_count: projects.size,
          total_amount: activity_rows.sum { |row| row[:total_amount].to_d },
          month_totals: month_totals_for(activity_rows),
          month_changes: month_changes_for(activity_rows),
          projects: projects
        }
      end
      .sort_by { |activity| [ -activity[:total_amount], activity[:activity_name].to_s ] }
  end

  def project_breakdown_for(rows)
    rows
      .group_by { |row| row[:project_name].presence || "Unassigned Project" }
      .map do |project_name, project_rows|
        {
          project_name: project_name,
          total_amount: project_rows.sum { |row| row[:total_amount].to_d }
        }
      end
      .sort_by { |project| [ -project[:total_amount], project[:project_name].to_s ] }
  end

  def month_totals_for(rows)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      rows.sum { |row| row[:month_amounts][month].to_d }
    end
  end

  def month_changes_for(rows)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      rows.filter_map do |row|
        delta = row[:month_deltas][month].to_d
        delta if delta.abs >= 0.01
      end
    end
  end

  def planned_month_amounts_for(total_amount, vertical_name)
    month_amounts_for(total_amount, VerticalPercent.find_by(vertical_name: vertical_name))
  end

  def month_deltas_for(month_amounts, planned_month_amounts)
    VerticalPercent::MONTH_COLUMNS.index_with do |month|
      month_amounts[month].to_d - planned_month_amounts[month].to_d
    end
  end

  def bli_code_lookup_for(submissions)
    submissions.each_with_object({}) do |submission, lookup|
      submission.employee.accessible_bli_activities.each do |activity|
        key = [ activity.project_name, activity.activity_name, activity.vertical_name ]
        lookup[key] ||= activity.bli_code
      end
    end
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

  def approval_record_entries_for(submissions)
    submissions.uniq(&:id).map do |submission|
      verticals = submission.project_summary_submission_items.map { |item| item.vertical_name.presence || "Unassigned Vertical" }.uniq.sort
      projects = submission.project_summary_submission_items.map(&:project_name).compact_blank.uniq.sort

      {
        status: submission.status,
        status_label: approval_record_status_label(submission),
        employee_name: submission.employee.name,
        vertical_name: verticals.join(", "),
        project_names: projects.join(", "),
        submitted_at: submission.submitted_at,
        action_at: submission.reviewed_at || submission.updated_at,
        remark: meaningful_approval_remark(submission),
        total_amount: submission.total_amount
      }
    end
  end

  def meaningful_approval_remark(submission)
    remark = submission.approval_remark.presence || submission.submission_remark.presence
    return nil if remark.blank?

    normalized = remark.to_s.strip.downcase
    return nil if normalized.in?(%w[approved approve forwarded forward return returned ok done yes])

    remark
  end

  def approval_record_status_label(submission)
    if submission.pending? && submission.first_approver_id.present?
      "Forwarded"
    elsif submission.approved?
      "Approved"
    elsif submission.returned?
      "Returned"
    else
      submission.status_label
    end
  end

  def filter_submissions_by_record_status(submissions, status_filter)
    case status_filter
    when "forwarded"
      submissions.select { |submission| submission.pending? && submission.first_approver_id.present? }
    when "approved"
      submissions.select(&:approved?)
    when "returned"
      submissions.select(&:returned?)
    else
      submissions
    end
  end
end

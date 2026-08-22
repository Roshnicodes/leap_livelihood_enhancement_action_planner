require "csv"

class ActionPlanStatusReport
  MONTHS = ActionPlanRow::MONTH_COLUMNS.freeze

  def fco_submission_rows
    @fco_submission_rows ||= fco_options.map do |state, fco_id, fco_name, fco_ids|
      month_details = MONTHS.index_with { |month| fco_month_submission_detail(fco_id, month) }
      statuses = month_details.transform_values { |detail| detail[:status] }

      {
        state: state,
        fco_id: fco_id,
        fco_name: fco_name,
        fco_ids: fco_ids,
        statuses: statuses,
        month_details: month_details,
        total_expected: month_details.values.sum { |detail| detail[:expected_count] },
        total_submitted: month_details.values.sum { |detail| detail[:submitted_count] },
        total_not_submitted: month_details.values.sum { |detail| detail[:not_submitted_count] },
        total_pending: month_details.values.sum { |detail| detail[:pending_count] },
        total_approved: month_details.values.sum { |detail| detail[:approved_count] },
        missing_projects: month_details.values.flat_map { |detail| detail[:not_submitted_projects] }.uniq
      }
    end
  end

  def summary_totals
    submitted_count = achievement_submissions.count { |submission| submission.pending? || submission.approved? }

    {
      submitted: submitted_count,
      approved: achievement_submissions.count(&:approved?),
      pending: achievement_submissions.count(&:pending?),
      not_submitted: fco_submission_rows.sum { |row| row[:total_not_submitted] }
    }
  end

  def fco_approval_rows
    @fco_approval_rows ||= fco_options.map do |state, fco_id, fco_name, fco_ids|
      statuses = MONTHS.index_with do |month|
        submission = achievement_submission_for(fco_id, month)
        submission ? status_label(submission) : "Not Submitted"
      end

      {
        state: state,
        fco_id: fco_id,
        fco_name: fco_name,
        fco_ids: fco_ids,
        statuses: statuses,
        total_pending: statuses.values.count { |status| status.start_with?("Pending") },
        total_approved: statuses.values.count("Approved"),
        total_returned: statuses.values.count("Returned")
      }
    end
  end

  def vertical_summary_rows
    vertical_mappings.map do |mapping|
      submissions = achievement_submissions.select do |submission|
        submission.state_code.to_s == mapping.state_code.to_s &&
          submission.theme_ids.include?(mapping.asa_theme_id.to_s)
      end
      total_fco = active_rows
        .where(statte: mapping.state_code, asa_theme_id: mapping.asa_theme_id)
        .distinct
        .count(:user_id)

      {
        vertical_name: mapping.asa_theme.presence || "ASA Theme #{mapping.asa_theme_id}",
        state: mapping.state_code,
        asa_theme_id: mapping.asa_theme_id,
        approver: mapping.employee&.name.presence || mapping.employee_code,
        total_fco: total_fco,
        pending_fco: submissions.select(&:pending?).map(&:fco_id).uniq.size,
        approved_fco: submissions.select(&:approved?).map(&:fco_id).uniq.size,
        returned_fco: submissions.select(&:returned?).map(&:fco_id).uniq.size
      }
    end
  end

  def action_plan_detail_rows
    ActionPlanSubmission
      .includes(:employee, :project_ownership, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
      .map do |submission|
        {
          project: submission.project_name,
          plan_type: submission.plan_type_label,
          submitted_by: employee_label(submission.employee),
          submitted_at: datetime(submission.submitted_at),
          status: status_label(submission),
          current_stage: submission.current_stage.to_s.titleize,
          po_approver: employee_label(submission.po_approver),
          po_status: stage_status(submission, "po"),
          coo_approver: employee_label(submission.coo_approver),
          coo_status: stage_status(submission, "coo"),
          director_view: stage_status(submission, "director"),
          remark: submission.submission_remark
        }
      end
  end

  def achievement_detail_rows
    achievement_submissions.map do |submission|
      {
        project: submission.project_name,
        state: submission.state_code,
        fco: ActionPlanFcoGroup.name_for(submission.fco_id, submission.fco_name),
        to: submission.to_name,
        vertical: submission.theme_label,
        month: submission.month.capitalize,
        submitted_by: employee_label(submission.employee),
        submitted_at: datetime(submission.submitted_at),
        status: status_label(submission),
        current_stage: submission.current_stage.to_s.titleize,
        vertical_approver: employee_label(submission.vertical_approver),
        vertical_status: stage_status(submission, "vertical"),
        po_approver: employee_label(submission.po_approver),
        po_status: stage_status(submission, "po"),
        coo_approver: employee_label(submission.coo_approver),
        coo_status: stage_status(submission, "coo"),
        director_view: stage_status(submission, "director"),
        remark: submission.submission_remark
      }
    end
  end

  def csv
    CSV.generate(headers: true) do |csv|
      append_fco_submission_csv(csv)
      csv << []
      append_fco_approval_csv(csv)
      csv << []
      append_vertical_summary_csv(csv)
      csv << []
      append_action_plan_details_csv(csv)
      csv << []
      append_achievement_details_csv(csv)
    end
  end

  def xlsx
    XlsxWorkbook.new(status_sheets).to_xlsx
  end

  private

  def status_sheets
    [
      {
        name: "Submitted",
        title: "Achievement Submitted Status",
        headers: [ "State", "FCO ID", "FCO", *month_headers, "Total Submitted", "Total Not Submitted", "Total Pending Approval", "Total Approved", "Not Submitted Projects" ],
        rows: fco_submission_rows.map do |row|
          [
            row[:state],
            row[:fco_ids].join(", "),
            row[:fco_name],
            *MONTHS.map { |month| submitted_export_value(row[:month_details][month]) },
            row[:total_submitted],
            row[:total_not_submitted],
            row[:total_pending],
            row[:total_approved],
            row[:missing_projects].join("; ")
          ]
        end,
        widths: [ 12, 10, 28, *Array.new(MONTHS.size, 24), 16, 18, 15, 15, 48 ]
      },
      {
        name: "Approval",
        title: "Achievement Approval Status",
        headers: [ "State", "FCO ID", "FCO", *month_headers, "Total Pending", "Total Approved", "Total Returned" ],
        rows: fco_approval_rows.map do |row|
          [ row[:state], row[:fco_ids].join(", "), row[:fco_name], *MONTHS.map { |month| row[:statuses][month] }, row[:total_pending], row[:total_approved], row[:total_returned] ]
        end,
        widths: [ 12, 10, 28, *Array.new(MONTHS.size, 22), 15, 15, 15 ]
      },
      {
        name: "Vertical Summary",
        title: "Verticals Wise Summary",
        headers: [ "Vertical Name", "State", "ASA Theme ID", "Approver", "Total FCO", "Pending FCO", "Approved FCO", "Returned FCO" ],
        rows: vertical_summary_rows.map do |row|
          [ row[:vertical_name], row[:state], row[:asa_theme_id], row[:approver], row[:total_fco], row[:pending_fco], row[:approved_fco], row[:returned_fco] ]
        end,
        widths: [ 42, 12, 14, 28, 12, 14, 14, 14 ]
      },
      {
        name: "Action Plan",
        title: "Action Plan Status Details",
        headers: [ "Project", "Plan Type", "Submitted By", "Submitted At", "Status", "Current Stage", "PO Approver", "PO Status", "COO Approver", "COO Status", "Director View", "Remark" ],
        rows: action_plan_detail_rows.map { |row| row.values },
        widths: [ 34, 18, 28, 22, 28, 18, 28, 24, 28, 24, 20, 36 ]
      },
      {
        name: "Achievement",
        title: "Achievement Status Details",
        headers: [ "Project", "State", "FCO", "TO", "Vertical", "Month", "Submitted By", "Submitted At", "Status", "Current Stage", "Vertical Approver", "Vertical Status", "PO Approver", "PO Status", "COO Approver", "COO Status", "Director View", "Remark" ],
        rows: achievement_detail_rows.map { |row| row.values },
        widths: [ 34, 10, 26, 26, 24, 12, 28, 22, 28, 18, 28, 24, 28, 24, 28, 24, 20, 36 ]
      }
    ]
  end

  def active_rows
    @active_rows ||= ActionPlanRow.active_import
  end

  def fco_options
    @fco_options ||= active_rows
      .where.not(user_id: [ nil, "" ])
      .distinct
      .order(:statte, :user_name, :user_id)
      .pluck(:statte, :user_id, :user_name)
      .group_by { |state, fco_id, _fco_name| [ state, ActionPlanFcoGroup.canonical_id(fco_id) ] }
      .map do |(state, canonical_id), rows|
        ids = rows.flat_map { |_row_state, fco_id, _fco_name| ActionPlanFcoGroup.ids_for(fco_id) }.uniq
        [ state, canonical_id, ActionPlanFcoGroup.name_for(canonical_id, rows.first.third), ids ]
      end
      .sort_by { |state, _fco_id, fco_name, _ids| [ state.to_s, fco_name.to_s ] }
  end

  def achievement_submissions
    @achievement_submissions ||= AchievementSubmission
      .includes(:employee, :vertical_approver, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
      .to_a
  end

  def achievement_submission_lookup
    @achievement_submission_lookup ||= achievement_submissions.each_with_object({}) do |submission, lookup|
      canonical_id = ActionPlanFcoGroup.canonical_id(submission.fco_id)
      key = [ canonical_id, submission.month.to_s ]
      lookup[key] = preferred_submission(lookup[key], submission)
    end
  end

  def achievement_submissions_by_fco_month
    @achievement_submissions_by_fco_month ||= achievement_submissions.group_by do |submission|
      [ ActionPlanFcoGroup.canonical_id(submission.fco_id), submission.month.to_s ]
    end
  end

  def fco_month_submission_detail(fco_id, month)
    expected_projects = expected_projects_for(fco_id, month)
    submissions = achievement_submissions_by_fco_month[[ ActionPlanFcoGroup.canonical_id(fco_id), month.to_s ]] || []
    project_submissions = preferred_project_submissions(submissions)
    submitted_projects = project_submissions.keys
    counted_submitted_projects = expected_projects.present? ? (expected_projects & submitted_projects) : submitted_projects
    approved_projects = counted_submitted_projects.select { |project| project_submissions[project]&.approved? }
    pending_projects = counted_submitted_projects.select { |project| project_submissions[project]&.pending? }
    not_submitted_projects = expected_projects - submitted_projects

    {
      status: submission_status(expected_projects, counted_submitted_projects),
      expected_count: expected_projects.size,
      submitted_count: counted_submitted_projects.size,
      approved_count: approved_projects.size,
      pending_count: pending_projects.size,
      not_submitted_count: not_submitted_projects.size,
      not_submitted_projects: not_submitted_projects,
      pending_projects: pending_projects
    }
  end

  def expected_projects_for(fco_id, month)
    key = [ ActionPlanFcoGroup.canonical_id(fco_id), month.to_s ]
    expected_projects_by_fco_month.fetch(key, [])
  end

  def expected_projects_by_fco_month
    @expected_projects_by_fco_month ||= begin
      lookup = Hash.new { |hash, key| hash[key] = [] }

      active_rows
        .where.not(user_id: [ nil, "" ], project_name: [ nil, "" ])
        .find_each do |row|
          canonical_id = ActionPlanFcoGroup.canonical_id(row.user_id)

          MONTHS.each do |month|
            next unless row.public_send(month).to_i.positive?

            lookup[[ canonical_id, month ]] << row.project_name.to_s.squish
          end
        end

      lookup.transform_values { |projects| projects.uniq.sort }
    end
  end

  def preferred_project_submissions(submissions)
    submissions.reject(&:returned?).each_with_object({}) do |submission, lookup|
      project_name = submission.project_name.to_s.squish
      next if project_name.blank?

      lookup[project_name] = preferred_submission(lookup[project_name], submission)
    end
  end

  def submission_status(expected_projects, submitted_projects)
    return "No Target" if expected_projects.empty?
    return "Not Submitted" if submitted_projects.empty?
    return "Partial" if submitted_projects.size < expected_projects.size

    "Submitted"
  end

  def submitted_export_value(detail)
    return detail[:status] if detail[:expected_count].zero?

    value = "#{detail[:status]} (#{detail[:submitted_count]}/#{detail[:expected_count]})"
    return value if detail[:not_submitted_projects].blank?

    "#{value}; Not submitted: #{detail[:not_submitted_projects].join(', ')}"
  end

  def achievement_submission_for(fco_id, month)
    achievement_submission_lookup[[ ActionPlanFcoGroup.canonical_id(fco_id), month.to_s ]]
  end

  def preferred_submission(existing, candidate)
    return candidate if existing.blank?
    return candidate if candidate.approved? && !existing.approved?
    return candidate if candidate.pending? && existing.returned?
    return candidate if candidate.submitted_at.to_i > existing.submitted_at.to_i

    existing
  end

  def vertical_mappings
    @vertical_mappings ||= ActionPlanVerticalMapping
      .includes(:employee)
      .order(:state_code, :asa_theme_id, :employee_code)
      .to_a
      .uniq { |mapping| [ mapping.state_code, mapping.asa_theme_id, mapping.employee_code ] }
  end

  def status_label(submission)
    submission.status_label
  end

  def stage_status(submission, stage)
    reviewed_at = submission.public_send("#{stage}_reviewed_at")
    return "Returned on #{datetime(reviewed_at)}" if reviewed_at.present? && submission.returned? && submission.current_stage == stage
    return "Approved on #{datetime(reviewed_at)}" if reviewed_at.present?
    return "Pending" if submission.pending? && submission.current_stage == stage
    return "View only" if stage == "director"

    "Awaiting"
  end

  def employee_label(employee)
    return "-" if employee.blank?

    [ employee.employee_code, employee.name ].compact_blank.join(" - ")
  end

  def datetime(value)
    value&.in_time_zone("Asia/Kolkata")&.strftime("%d %b %Y, %I:%M %p")
  end

  def append_fco_submission_csv(csv)
    csv << [ "Achievement Submitted Status" ]
    csv << [ "State", "FCO ID", "FCO", *month_headers, "Total Submitted", "Total Not Submitted", "Total Pending Approval", "Total Approved", "Not Submitted Projects" ]
    fco_submission_rows.each do |row|
      csv << [
        row[:state],
        row[:fco_ids].join(", "),
        row[:fco_name],
        *MONTHS.map { |month| submitted_export_value(row[:month_details][month]) },
        row[:total_submitted],
        row[:total_not_submitted],
        row[:total_pending],
        row[:total_approved],
        row[:missing_projects].join("; ")
      ]
    end
  end

  def append_fco_approval_csv(csv)
    csv << [ "Achievement Approval Status" ]
    csv << [ "State", "FCO ID", "FCO", *month_headers, "Total Pending", "Total Approved", "Total Returned" ]
    fco_approval_rows.each do |row|
      csv << [ row[:state], row[:fco_ids].join(", "), row[:fco_name], *MONTHS.map { |month| row[:statuses][month] }, row[:total_pending], row[:total_approved], row[:total_returned] ]
    end
  end

  def append_vertical_summary_csv(csv)
    csv << [ "Verticals Wise Summary" ]
    csv << [ "Vertical Name", "State", "ASA Theme ID", "Approver", "Total FCO", "No. of FCO Pending for Approval", "No. of FCO Approved", "No. of FCO Returned" ]
    vertical_summary_rows.each do |row|
      csv << [ row[:vertical_name], row[:state], row[:asa_theme_id], row[:approver], row[:total_fco], row[:pending_fco], row[:approved_fco], row[:returned_fco] ]
    end
  end

  def append_action_plan_details_csv(csv)
    csv << [ "Action Plan Status Details" ]
    csv << [ "Project", "Plan Type", "Submitted By", "Submitted At", "Status", "Current Stage", "PO Approver", "PO Status", "COO Approver", "COO Status", "Director View", "Remark" ]
    action_plan_detail_rows.each { |row| csv << row.values }
  end

  def append_achievement_details_csv(csv)
    csv << [ "Achievement Status Details" ]
    csv << [ "Project", "State", "FCO", "TO", "Vertical", "Month", "Submitted By", "Submitted At", "Status", "Current Stage", "Vertical Approver", "Vertical Status", "PO Approver", "PO Status", "COO Approver", "COO Status", "Director View", "Remark" ]
    achievement_detail_rows.each { |row| csv << row.values }
  end

  def month_headers
    MONTHS.map(&:capitalize)
  end
end

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
        project_count: expected_projects_for(fco_id).size,
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
    {
      # Keep every headline metric on the same unit as the FCO grid: one
      # assigned project for one reporting month. Counting database submissions
      # here was misleading because one project can create more than one review
      # package (for example, for separate vertical approvers).
      submitted: fco_submission_rows.sum { |row| row[:total_submitted] },
      approved: fco_submission_rows.sum { |row| row[:total_approved] },
      pending: fco_submission_rows.sum { |row| row[:total_pending] },
      not_submitted: fco_submission_rows.sum { |row| row[:total_not_submitted] }
    }
  end

  def fco_approval_rows
    @fco_approval_rows ||= fco_options.map do |state, fco_id, fco_name, fco_ids|
      month_details = MONTHS.index_with do |month|
        fco_month_approval_detail(fco_id, month)
      end

      {
        state: state,
        fco_id: fco_id,
        fco_name: fco_name,
        fco_ids: fco_ids,
        project_count: expected_projects_for(fco_id).size,
        month_details: month_details,
        total_pending: month_details.values.sum { |detail| detail[:pending_count] },
        total_approved: month_details.values.sum { |detail| detail[:approved_count] },
        total_returned: month_details.values.sum { |detail| detail[:returned_count] }
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
        pending_fco: submissions.select(&:pending?).map { |submission| ActionPlanFcoGroup.canonical_id(submission.fco_id) }.uniq.size,
        approved_fco: submissions.select(&:approved?).map { |submission| ActionPlanFcoGroup.canonical_id(submission.fco_id) }.uniq.size,
        returned_fco: submissions.select(&:returned?).map { |submission| ActionPlanFcoGroup.canonical_id(submission.fco_id) }.uniq.size
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
        vertical_reviewed_at: datetime(submission.vertical_reviewed_at),
        vertical_status: stage_status(submission, "vertical"),
        po_approver: employee_label(submission.po_approver),
        po_reviewed_at: datetime(submission.po_reviewed_at),
        po_status: stage_status(submission, "po"),
        coo_approver: employee_label(submission.coo_approver),
        coo_reviewed_at: datetime(submission.coo_reviewed_at),
        coo_status: stage_status(submission, "coo"),
        director_approver: employee_label(submission.director_approver),
        director_reviewed_at: datetime(submission.director_reviewed_at),
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
        headers: [ "State", "FCO ID", "FCO", *month_headers, "Submitted Project-Months", "Not Submitted Project-Months", "Pending Project-Months", "Approved Project-Months", "Not Submitted Projects" ],
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
        headers: [ "State", "FCO ID", "FCO", *month_headers, "Pending Project-Months", "Approved Project-Months", "Returned Project-Months" ],
        rows: fco_approval_rows.map do |row|
          [ row[:state], row[:fco_ids].join(", "), row[:fco_name], *MONTHS.map { |month| approval_export_value(row[:month_details][month]) }, row[:total_pending], row[:total_approved], row[:total_returned] ]
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
        headers: [ "Project", "State", "FCO", "TO", "Vertical", "Month", "Submitted By", "Submitted At", "Status", "Current Stage", "Vertical Approver", "Vertical Reviewed At", "Vertical Status", "PO Approver", "PO Reviewed At", "PO Status", "COO Approver", "COO Reviewed At", "COO Status", "Director Approver", "Director Reviewed At", "Director View", "Remark" ],
        rows: achievement_detail_rows.map { |row| row.values },
        widths: [ 34, 10, 26, 26, 24, 12, 28, 22, 28, 18, 28, 22, 24, 28, 22, 24, 28, 22, 24, 28, 22, 20, 36 ]
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
      .group_by { |_state, fco_id, _fco_name| ActionPlanFcoGroup.canonical_id(fco_id) }
      .map do |canonical_id, rows|
        state = rows.map(&:first).compact_blank.uniq.sort.join(", ")
        ids = rows.flat_map { |_row_state, fco_id, _fco_name| ActionPlanFcoGroup.ids_for(fco_id) }.uniq
        [ state, canonical_id, ActionPlanFcoGroup.name_for(canonical_id, preferred_fco_name(rows)), ids ]
      end
      .sort_by { |state, _fco_id, fco_name, _ids| [ state.to_s, fco_name.to_s ] }
  end

  def preferred_fco_name(rows)
    rows
      .map(&:third)
      .compact_blank
      .tally
      .max_by { |name, count| [ count, name ] }
      &.first
  end

  def achievement_submissions
    @achievement_submissions ||= AchievementSubmission
      .where(mis_submitted: false)
      .includes(:employee, :vertical_approver, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
      .to_a
  end

  def achievement_submissions_by_fco_month
    @achievement_submissions_by_fco_month ||= achievement_submissions.group_by do |submission|
      [ ActionPlanFcoGroup.canonical_id(submission.fco_id), submission.month.to_s ]
    end
  end

  def fco_month_submission_detail(fco_id, month)
    expected_projects = expected_projects_for(fco_id)
    submissions = achievement_submissions_by_fco_month[[ ActionPlanFcoGroup.canonical_id(fco_id), month.to_s ]] || []
    project_states = project_submission_states(submissions)
    detail = project_month_counts(expected_projects, project_states)

    {
      status: submission_status(expected_projects, detail[:submitted_projects]),
      expected_count: expected_projects.size,
      submitted_count: detail[:submitted_projects].size,
      approved_count: detail[:approved_projects].size,
      pending_count: detail[:pending_projects].size,
      returned_count: detail[:returned_projects].size,
      not_submitted_count: detail[:not_submitted_projects].size,
      not_submitted_projects: detail[:not_submitted_projects],
      pending_projects: detail[:pending_projects],
      returned_projects: detail[:returned_projects],
      audit_lines: submission_audit_lines(detail[:audit_submissions])
    }
  end

  def fco_month_approval_detail(fco_id, month)
    expected_projects = expected_projects_for(fco_id)
    submissions = achievement_submissions_by_fco_month[[ ActionPlanFcoGroup.canonical_id(fco_id), month.to_s ]] || []
    detail = project_month_counts(expected_projects, project_submission_states(submissions))

    {
      status: approval_status(expected_projects, detail),
      status_kind: approval_status_kind(expected_projects, detail),
      expected_count: expected_projects.size,
      submitted_count: detail[:submitted_projects].size,
      approved_count: detail[:approved_projects].size,
      pending_count: detail[:pending_projects].size,
      returned_count: detail[:returned_projects].size,
      not_submitted_count: detail[:not_submitted_projects].size,
      audit_lines: submission_audit_lines(detail[:audit_submissions])
    }
  end

  # An FCO's assigned project list is a master-data relationship, not a target
  # calendar. A project with a zero target in a particular month is still an
  # assigned project and must remain in the report denominator for every month.
  def expected_projects_for(fco_id)
    expected_projects_by_fco.fetch(ActionPlanFcoGroup.canonical_id(fco_id), [])
  end

  def expected_projects_by_fco
    @expected_projects_by_fco ||= begin
      lookup = Hash.new { |hash, key| hash[key] = [] }

      active_rows
        .where.not(user_id: [ nil, "" ], project_name: [ nil, "" ])
        .find_each do |row|
          canonical_id = ActionPlanFcoGroup.canonical_id(row.user_id)
          lookup[canonical_id] << row.project_name.to_s.squish
        end

      lookup.transform_values { |projects| projects.uniq.sort }
    end
  end

  def project_submission_states(submissions)
    submissions.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |submission, grouped|
      project_name = submission.project_name.to_s.squish
      next if project_name.blank?

      grouped[project_name] << submission
    end.transform_values do |project_submissions|
      active_submissions = project_submissions.select { |submission| submission.pending? || submission.approved? }
      latest_inactive = project_submissions
        .reject { |submission| submission.pending? || submission.approved? }
        .max_by { |submission| [ submission.submitted_at.to_i, submission.id.to_i ] }

      {
        active: active_submissions.present?,
        approved: active_submissions.present? && active_submissions.all?(&:approved?),
        pending: active_submissions.any?(&:pending?),
        returned: active_submissions.blank? && project_submissions.any?(&:returned?),
        audit_submissions: active_submissions.presence || Array(latest_inactive)
      }
    end
  end

  def project_month_counts(expected_projects, project_states)
    expected_states = expected_projects.index_with { |project| project_states[project] || {} }
    submitted_projects = expected_states.filter_map { |project, state| project if state[:active] }
    approved_projects = expected_states.filter_map { |project, state| project if state[:approved] }
    pending_projects = expected_states.filter_map { |project, state| project if state[:pending] }
    returned_projects = expected_states.filter_map { |project, state| project if state[:returned] }
    not_submitted_projects = expected_projects - submitted_projects

    {
      submitted_projects: submitted_projects,
      approved_projects: approved_projects,
      pending_projects: pending_projects,
      returned_projects: returned_projects,
      not_submitted_projects: not_submitted_projects,
      audit_submissions: expected_states.values.flat_map { |state| state[:audit_submissions] }.compact
    }
  end

  def submission_status(expected_projects, submitted_projects)
    return "No Projects" if expected_projects.empty?
    return "Not Submitted" if submitted_projects.empty?
    return "Partial" if submitted_projects.size < expected_projects.size

    "Submitted"
  end

  def approval_status(expected_projects, detail)
    return "No Projects" if expected_projects.empty?
    return "Approved #{detail[:approved_projects].size}/#{expected_projects.size}" if detail[:approved_projects].size == expected_projects.size
    if detail[:pending_projects].present?
      label = "Pending #{detail[:pending_projects].size}/#{expected_projects.size}"
      return detail[:returned_projects].present? ? "#{label} · #{detail[:returned_projects].size} Returned" : label
    end
    return "Returned #{detail[:returned_projects].size}/#{expected_projects.size}" if detail[:returned_projects].present?

    "Not Submitted 0/#{expected_projects.size}"
  end

  def approval_status_kind(expected_projects, detail)
    return "not_submitted" if expected_projects.empty?
    return "approved" if detail[:approved_projects].size == expected_projects.size
    return "pending" if detail[:pending_projects].present?
    return "returned" if detail[:returned_projects].present?

    "not_submitted"
  end

  def submitted_export_value(detail)
    return detail[:status] if detail[:expected_count].zero?

    value = "#{detail[:status]} (#{detail[:submitted_count]}/#{detail[:expected_count]})"
    value = [ value, *detail[:audit_lines] ].compact_blank.join("; ")
    return value if detail[:not_submitted_projects].blank?

    "#{value}; Not submitted: #{detail[:not_submitted_projects].join(', ')}"
  end

  def approval_export_value(detail)
    [ detail[:status], *detail[:audit_lines] ].compact_blank.join("; ")
  end

  def vertical_mappings
    @vertical_mappings ||= ActionPlanVerticalMapping.active
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

  def submission_audit_lines(submissions)
    submissions = submissions.compact
    return [] if submissions.blank?

    [
      submitted_audit_line(submissions),
      latest_review_audit_line(submissions)
    ].compact
  end

  def submitted_audit_line(submissions)
    submitted_times = submissions.filter_map(&:submitted_at)
    return if submitted_times.blank?

    submitted_by = submissions.map { |submission| employee_label(submission.employee) }.reject { |label| label == "-" }.uniq
    label = submitted_times.size > 1 ? "Submitted #{datetime(submitted_times.min)} - #{datetime(submitted_times.max)}" : "Submitted #{datetime(submitted_times.first)}"
    submitted_by.present? ? "#{label} by #{submitted_by.to_sentence}" : label
  end

  def latest_review_audit_line(submissions)
    reviews = submissions.flat_map do |submission|
      %w[vertical po coo director].filter_map do |stage|
        reviewed_at = submission.public_send("#{stage}_reviewed_at")
        next if reviewed_at.blank?

        returned = submission.returned? && submission.current_stage == stage
        {
          reviewed_at: reviewed_at,
          label: returned ? "Returned" : "Approved",
          stage: stage,
          actor: employee_label(submission.public_send("#{stage}_approver"))
        }
      end
    end
    review = reviews.max_by { |item| item[:reviewed_at] }
    return if review.blank?

    actor = review[:actor] == "-" ? review[:stage].titleize : review[:actor]
    "#{review[:label]} by #{actor} on #{datetime(review[:reviewed_at])}"
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
    csv << [ "State", "FCO ID", "FCO", *month_headers, "Submitted Project-Months", "Not Submitted Project-Months", "Pending Project-Months", "Approved Project-Months", "Not Submitted Projects" ]
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
    csv << [ "State", "FCO ID", "FCO", *month_headers, "Pending Project-Months", "Approved Project-Months", "Returned Project-Months" ]
    fco_approval_rows.each do |row|
      csv << [ row[:state], row[:fco_ids].join(", "), row[:fco_name], *MONTHS.map { |month| approval_export_value(row[:month_details][month]) }, row[:total_pending], row[:total_approved], row[:total_returned] ]
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
    csv << [ "Project", "State", "FCO", "TO", "Vertical", "Month", "Submitted By", "Submitted At", "Status", "Current Stage", "Vertical Approver", "Vertical Reviewed At", "Vertical Status", "PO Approver", "PO Reviewed At", "PO Status", "COO Approver", "COO Reviewed At", "COO Status", "Director Approver", "Director Reviewed At", "Director View", "Remark" ]
    achievement_detail_rows.each { |row| csv << row.values }
  end

  def month_headers
    MONTHS.map(&:capitalize)
  end
end

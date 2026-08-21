require "csv"

class ActionPlanStatusReport
  MONTHS = ActionPlanRow::MONTH_COLUMNS.freeze

  def fco_submission_rows
    fco_options.map do |state, fco_id, fco_name|
      statuses = MONTHS.index_with { |month| achievement_submission_for(fco_id, month).present? ? "Yes" : "No" }

      {
        state: state,
        fco_id: fco_id,
        fco_name: fco_name,
        statuses: statuses,
        total_submitted: statuses.values.count("Yes"),
        total_pending: MONTHS.count { |month| achievement_submission_for(fco_id, month)&.pending? },
        total_approved: MONTHS.count { |month| achievement_submission_for(fco_id, month)&.approved? }
      }
    end
  end

  def fco_approval_rows
    fco_options.map do |state, fco_id, fco_name|
      statuses = MONTHS.index_with do |month|
        submission = achievement_submission_for(fco_id, month)
        submission ? status_label(submission) : "Not Submitted"
      end

      {
        state: state,
        fco_id: fco_id,
        fco_name: fco_name,
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
        fco: submission.fco_name,
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
        headers: [ "State", "FCO ID", "FCO", *month_headers, "Total Submitted", "Total Pending", "Total Approved" ],
        rows: fco_submission_rows.map do |row|
          [ row[:state], row[:fco_id], row[:fco_name], *MONTHS.map { |month| row[:statuses][month] }, row[:total_submitted], row[:total_pending], row[:total_approved] ]
        end,
        widths: [ 12, 10, 28, *Array.new(MONTHS.size, 14), 16, 15, 15 ]
      },
      {
        name: "Approval",
        title: "Achievement Approval Status",
        headers: [ "State", "FCO ID", "FCO", *month_headers, "Total Pending", "Total Approved", "Total Returned" ],
        rows: fco_approval_rows.map do |row|
          [ row[:state], row[:fco_id], row[:fco_name], *MONTHS.map { |month| row[:statuses][month] }, row[:total_pending], row[:total_approved], row[:total_returned] ]
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
  end

  def achievement_submissions
    @achievement_submissions ||= AchievementSubmission
      .includes(:employee, :vertical_approver, :po_approver, :coo_approver, :director_approver)
      .order(submitted_at: :desc)
      .to_a
  end

  def achievement_submission_lookup
    @achievement_submission_lookup ||= achievement_submissions.each_with_object({}) do |submission, lookup|
      lookup[[ submission.fco_id.to_s, submission.month.to_s ]] ||= submission
    end
  end

  def achievement_submission_for(fco_id, month)
    achievement_submission_lookup[[ fco_id.to_s, month.to_s ]]
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
    return "Approved on #{datetime(reviewed_at)}" if reviewed_at.present? && !submission.returned?
    return "Returned on #{datetime(reviewed_at)}" if reviewed_at.present? && submission.returned? && submission.current_stage == stage
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
    csv << [ "State", "FCO ID", "FCO", *month_headers, "Total Submitted", "Total Pending", "Total Approved" ]
    fco_submission_rows.each do |row|
      csv << [ row[:state], row[:fco_id], row[:fco_name], *MONTHS.map { |month| row[:statuses][month] }, row[:total_submitted], row[:total_pending], row[:total_approved] ]
    end
  end

  def append_fco_approval_csv(csv)
    csv << [ "Achievement Approval Status" ]
    csv << [ "State", "FCO ID", "FCO", *month_headers, "Total Pending", "Total Approved", "Total Returned" ]
    fco_approval_rows.each do |row|
      csv << [ row[:state], row[:fco_id], row[:fco_name], *MONTHS.map { |month| row[:statuses][month] }, row[:total_pending], row[:total_approved], row[:total_returned] ]
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

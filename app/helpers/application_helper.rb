module ApplicationHelper
  CURRENCY_UNIT = "₹".freeze

  def currency(amount)
    value = amount.to_d.round
    sign = value.negative? ? "-" : ""
    "#{sign}#{CURRENCY_UNIT}#{indian_number_delimiter(value.abs.to_i)}"
  end

  def currency_input_value(amount)
    number_with_precision(amount, precision: 0, delimiter: "", separator: ".")
  end

  def action_plan_cell(value, pill: false, decimal: false)
    text = value
    text = ActionPlanRow.format_decimal_string(text) if decimal && text.present?
    text = ActionPlanRow.format_decimal_string(text) if !decimal && text.to_s.match?(/\A-?\d+\.\d+[0-9]{6,}\z/)
    text = text.presence || "-"
    return content_tag(:span, text, class: "code-pill") if pill

    text
  end

  def rounded_month_total(month_amounts)
    VerticalPercent::MONTH_COLUMNS.sum { |month| month_amounts[month].to_d.round }
  end

  def approval_actor_label(employee, fallback = "Approver")
    return fallback if employee.blank?
    return "you" if current_user&.employee&.id == employee.id

    employee.name.presence || fallback
  end

  def summary_approval_status_label(submission)
    return "Not Submitted" if submission.blank?
    return "Forwarded" if submission.pending? && submission.first_approver_id.present?

    submission.status_label
  end

  def summary_approval_headline(submission)
    return "Not submitted" if submission.blank?

    if submission.pending?
      approver = submission.approver || ProjectSummarySubmission.approver_employee
      if submission.first_approver_id.present?
        "Forwarded to #{approval_actor_label(approver)}"
      else
        "Sent to #{approval_actor_label(approver)}"
      end
    elsif submission.approved?
      "Approved by #{approval_actor_label(submission.approver)}"
    else
      "Returned by #{approval_actor_label(submission.approver)}"
    end
  end

  def summary_approval_subline(submission)
    return if submission.blank?
    return unless submission.first_approver.present?

    "Forwarded by #{approval_actor_label(submission.first_approver)}"
  end

  def summary_approval_remark_label(submission)
    return if submission.blank? || submission.approval_remark.blank?

    if submission.returned?
      "Return remark"
    elsif submission.pending? && submission.first_approver_id.present?
      "Forward remark"
    else
      "Approval remark"
    end
  end

  def approval_record_status_detail(submission)
    return "-" if submission.blank?

    if submission.pending? && submission.first_approver_id.present?
      "Pending with #{approval_actor_label(submission.approver)}"
    elsif submission.pending?
      "Pending with #{approval_actor_label(submission.approver || ProjectSummarySubmission.approver_employee)}"
    elsif submission.approved?
      approval_action_line("Approved by", submission.approver, submission.reviewed_at)
    elsif submission.returned?
      approval_action_line("Returned by", submission.approver, submission.reviewed_at)
    else
      submission.status_label
    end
  end

  def approval_record_status_badge(submission)
    return "not_submitted" if submission.blank?
    return "forwarded" if submission.pending? && submission.first_approver_id.present?

    submission.status
  end

  def approval_record_first_stage_line(submission)
    return if submission.blank?
    return unless submission.first_approver.present?

    approval_action_line(
      "Approved by",
      submission.first_approver,
      submission.first_approved_at || submission.updated_at
    )
  end

  def approval_record_coo_status(submission)
    return empty_approval_status if submission.blank?

    coo = ProjectSummarySubmission.first_approver_employee

    if submission.first_approver_id.present?
      approval_status_result(
        approval_action_line("Approved by", submission.first_approver, submission.first_approved_at || submission.updated_at),
        "approved"
      )
    elsif submission.returned? && submission.approver_id == coo&.id
      approval_status_result(
        approval_action_line("Returned by", submission.approver, submission.reviewed_at),
        "returned"
      )
    elsif submission.pending?
      approval_status_result(
        "Pending with #{approval_actor_label(coo)}",
        "pending"
      )
    else
      empty_approval_status
    end
  end

  def approval_record_director_status(submission)
    return empty_approval_status if submission.blank?

    director = ProjectSummarySubmission.final_approver_employee

    if submission.approved?
      approval_status_result(
        approval_action_line("Approved by", submission.approver, submission.reviewed_at),
        "approved"
      )
    elsif submission.returned? && submission.first_approver_id.present?
      approval_status_result(
        approval_action_line("Returned by", submission.approver, submission.reviewed_at),
        "returned"
      )
    elsif submission.pending? && submission.first_approver_id.present?
      approval_status_result(
        "Pending with #{approval_actor_label(submission.approver || director)}",
        "forwarded"
      )
    else
      approval_status_result("Awaiting COO", "not_submitted")
    end
  end

  def approval_action_line(prefix, employee, timestamp)
    label = "#{prefix} #{approval_actor_label(employee)}"
    formatted_time = format_record_datetime(timestamp)
    formatted_time.present? ? "#{label} • #{formatted_time}" : label
  end

  def format_record_datetime(timestamp)
    return if timestamp.blank?

    timestamp.strftime("%d %b %Y, %I:%M %p")
  end

  def approval_status_result(label, badge)
    { label: label, badge: badge }
  end

  def empty_approval_status
    { label: "-", badge: "not_submitted" }
  end

  private

  def indian_number_delimiter(integer)
    digits = integer.to_s
    return digits if digits.length <= 3

    last_three = digits[-3, 3]
    leading = digits[0...-3].gsub(/(\d)(?=(\d{2})+(?!\d))/, '\1,')
    "#{leading},#{last_three}"
  end
end

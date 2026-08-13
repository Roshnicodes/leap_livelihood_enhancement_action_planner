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

  def whole_number(amount)
    value = amount.to_d.round
    sign = value.negative? ? "-" : ""
    "#{sign}#{indian_number_delimiter(value.abs.to_i)}"
  end

  def action_plan_cell(value, pill: false, decimal: false)
    text = value
    text = ActionPlanRow.format_decimal_string(text) if decimal && text.present?
    text = ActionPlanRow.format_decimal_string(text) if !decimal && text.to_s.match?(/\A-?\d+\.\d+[0-9]{6,}\z/)
    text = text.presence || "-"
    return content_tag(:span, text, class: "code-pill") if pill

    text
  end

  def month_column_header(name, metric)
    content_tag(:span, class: "month-head") do
      content_tag(:span, name) + content_tag(:span, metric)
    end
  end

  ACTION_PLAN_STAGE_TITLES = { "po" => "Project Owner", "coo" => "COO", "director" => "Director" }.freeze

  def signed_number(value)
    value.positive? ? "+#{value}" : value.to_s
  end

  # Stage whose approver the status headline talks about. Once a plan clears the
  # last approval stage (COO) its current_stage becomes "complete".
  def action_plan_headline_stage(submission)
    return "coo" if submission.current_stage.to_s.in?(%w[complete director]) || submission.approved?

    stages = ACTION_PLAN_STAGE_TITLES.keys
    return "coo" unless stages.include?(submission.current_stage)

    submission.current_stage
  end

  def action_plan_status_state(submission)
    return "not_submitted" if submission.blank?
    return submission.status unless submission.pending?

    submission.current_stage == "po" ? "pending" : "forwarded"
  end

  def action_plan_status_badge_label(submission)
    {
      "not_submitted" => "Not Submitted",
      "pending" => "Pending Approval",
      "forwarded" => "Forwarded",
      "approved" => "Approved",
      "returned" => "Returned"
    }.fetch(action_plan_status_state(submission), "Pending Approval")
  end

  def action_plan_approval_headline(submission)
    return "Not submitted" if submission.blank?

    stage = action_plan_headline_stage(submission)
    actor = action_plan_stage_actor(submission, stage)

    return "Approved by #{actor}" if submission.approved?
    return "Returned by #{actor}" if submission.returned?
    return "Sent to #{actor}" if stage == "po"

    "Forwarded to #{actor}"
  end

  def action_plan_approval_subline(submission)
    return if submission.blank?

    stages = ACTION_PLAN_STAGE_TITLES.keys
    headline_index = stages.index(action_plan_headline_stage(submission)) || stages.size
    previous = stages.first(headline_index).reverse.find do |stage|
      submission.public_send("#{stage}_reviewed_at").present?
    end
    return if previous.blank?

    "Forwarded by #{action_plan_stage_actor(submission, previous)}"
  end

  def action_plan_last_reviewed_at(submission)
    return if submission.blank?

    ACTION_PLAN_STAGE_TITLES.keys.filter_map { |stage| submission.public_send("#{stage}_reviewed_at") }.max
  end

  def action_plan_last_review_remark(submission)
    return if submission.blank?

    stage = ACTION_PLAN_STAGE_TITLES.keys.reverse.find do |candidate|
      submission.public_send("#{candidate}_reviewed_at").present?
    end
    return if stage.blank?

    submission.public_send("#{stage}_remark").presence
  end

  # Per-stage badge for the approval table: who acted, or who it is waiting on.
  def action_plan_stage_status(submission, stage)
    stages = ACTION_PLAN_STAGE_TITLES.keys
    reviewed_at = submission.public_send("#{stage}_reviewed_at")

    if reviewed_at.present?
      returned = submission.returned? && submission.current_stage == stage
      verb = returned ? "Returned" : "Approved"

      {
        label: "#{verb} by #{action_plan_stage_actor(submission, stage)} • #{format_record_datetime(reviewed_at)}",
        badge: returned ? "returned" : "approved"
      }
    elsif stage == "director"
      if submission.approved?
        { label: "View only • Final at COO", badge: "approved" }
      else
        { label: "View only", badge: "not_submitted" }
      end
    elsif submission.current_stage == stage
      {
        label: "Pending with #{action_plan_stage_actor(submission, stage)}",
        badge: stage == stages.first ? "pending" : "forwarded"
      }
    else
      index = stages.index(stage).to_i
      previous = stages[index - 1] if index.positive?

      {
        label: previous ? "Awaiting #{ACTION_PLAN_STAGE_TITLES.fetch(previous)}" : "-",
        badge: "not_submitted"
      }
    end
  end

  def action_plan_stage_actor(submission, stage)
    title = ACTION_PLAN_STAGE_TITLES.fetch(stage, "Approver")
    approval_actor_label(submission.public_send("#{stage}_approver"), title)
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
        "Pending with #{approval_actor_label(director)}",
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

    timestamp.in_time_zone("Asia/Kolkata").strftime("%d %b %Y, %I:%M %p")
  end

  def approval_status_result(label, badge)
    { label: label, badge: badge }
  end

  def empty_approval_status
    { label: "-", badge: "not_submitted" }
  end

  def attachment_preview_kind(attachment)
    blob = attachment.respond_to?(:blob) ? attachment.blob : attachment
    return "image" if blob.image?
    return "pdf" if blob.content_type.to_s == "application/pdf"
    return "video" if blob.content_type.to_s.start_with?("video/")
    return "audio" if blob.content_type.to_s.start_with?("audio/")

    "file"
  end

  def attachment_extension_label(attachment)
    blob = attachment.respond_to?(:blob) ? attachment.blob : attachment
    ext = File.extname(blob.filename.to_s).delete(".").upcase
    ext.presence || "FILE"
  end

  def attachment_inline_path(attachment)
    rails_blob_path(attachment, disposition: "inline")
  end

  def attachment_download_path(attachment)
    rails_blob_path(attachment, disposition: "attachment")
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

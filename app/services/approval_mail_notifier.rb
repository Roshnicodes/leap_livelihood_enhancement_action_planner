# Mails everyone an approval step concerns, through LeapMailRelay:
#
# - submitted / resubmitted   -> the approver who has to act now
# - approved at a level       -> the submitter, and the next level's approver
# - finally approved          -> the submitter
# - returned (with remark)    -> the submitter
#
# Called after commit from ActionPlanSubmission, AchievementSubmission and
# ProjectSummarySubmission, so it only sees saved changes and a mail failure
# can never roll back an approval.
class ApprovalMailNotifier
  STAGE_LABELS = {
    "vertical" => "Vertical Head",
    "po" => "Project Owner",
    "coo" => "COO",
    "director" => "Director"
  }.freeze
  REVIEW_STAGES = %w[vertical po coo director].freeze
  SIGNATURE = "LEAP - Action For Social Advancement (ASA)".freeze

  def self.call(submission)
    new(submission).call
  rescue StandardError => error
    Rails.logger.error("ApprovalMailNotifier failed for #{submission.class.name}##{submission.id}: #{error.class} #{error.message}")
  end

  def initialize(submission)
    @submission = submission
  end

  def call
    return unless LeapMailRelay.enabled?

    if staged?
      notify_staged
    else
      notify_project_summary
    end
  end

  private

  attr_reader :submission

  def staged?
    submission.respond_to?(:current_stage)
  end

  def status_changed_to?(status)
    submission.saved_change_to_status? && submission.status == status
  end

  def resubmitted?
    submission.saved_change_to_submitted_at? && submission.pending?
  end

  # ActionPlanSubmission / AchievementSubmission: vertical -> po -> coo -> complete.
  def notify_staged
    stage = submission.current_stage

    if resubmitted?
      mail_pending_approver(stage)
    elsif status_changed_to?("returned")
      mail_submitter_returned(STAGE_LABELS[stage], submission.public_send("#{stage}_approver"), submission.public_send("#{stage}_remark"))
    elsif status_changed_to?("approved")
      acted = submission.saved_change_to_current_stage&.first.presence_in(REVIEW_STAGES) || stage
      mail_submitter_approved(STAGE_LABELS[acted], submission.public_send("#{acted}_approver"), submission.public_send("#{acted}_remark"), final: true)
    elsif submission.pending? && submission.saved_change_to_current_stage?
      acted = submission.saved_change_to_current_stage.first
      if REVIEW_STAGES.include?(acted)
        mail_submitter_approved(STAGE_LABELS[acted], submission.public_send("#{acted}_approver"), submission.public_send("#{acted}_remark"), final: false, next_stage: stage)
      end
      mail_pending_approver(stage)
    end
  end

  # ProjectSummarySubmission: first approver -> final approver.
  def notify_project_summary
    if resubmitted?
      mail_pending_approver(nil)
    elsif status_changed_to?("returned")
      mail_submitter_returned("Approver", submission.approver, submission.approval_remark)
    elsif status_changed_to?("approved")
      mail_submitter_approved("Final Approver", submission.approver, submission.approval_remark, final: true)
    elsif submission.pending? && submission.saved_change_to_approver_id? && submission.saved_change_to_first_approved_at?
      mail_submitter_approved("First Approver", submission.first_approver, submission.approval_remark, final: false)
      mail_pending_approver(nil)
    end
  end

  def mail_pending_approver(stage)
    approver = stage ? submission.public_send("#{stage}_approver") : submission.approver
    by = submission.employee&.name.presence || "Employee"
    message = "#{subject_label} has been submitted by #{by} and is pending your approval"
    message += stage ? " as #{STAGE_LABELS[stage]}." : "."
    message += " Remarks: #{submission.submission_remark}" if submission.submission_remark.present?
    message += " Please review it in LEAP. #{SIGNATURE}"

    LeapMailRelay.notify(
      "#{kind_prefix}_pending",
      recipient: approver,
      subject: "Approval pending: #{subject_label}",
      message: message,
      path: approver_path(stage)
    )
  end

  def mail_submitter_approved(level, actor, remark, final:, next_stage: nil)
    message = "Your #{subject_label} has been approved by #{actor_text(level, actor)}."
    message += " It is now pending with #{STAGE_LABELS[next_stage]}." if !final && next_stage
    message += " It is now pending with the next approver." if !final && next_stage.nil?
    message += " Remarks: #{remark}" if remark.present?
    message += " #{SIGNATURE}"

    LeapMailRelay.notify(
      "#{kind_prefix}_#{final ? "approved" : "level_approved"}",
      recipient: submission.employee,
      subject: "#{final ? "Approved" : "Approved by #{level}"}: #{subject_label}",
      message: message,
      path: submitter_path
    )
  end

  def mail_submitter_returned(level, actor, remark)
    message = "Your #{subject_label} has been returned by #{actor_text(level, actor)}. Please check and resubmit."
    message += " Remarks: #{remark}" if remark.present?
    message += " #{SIGNATURE}"

    LeapMailRelay.notify(
      "#{kind_prefix}_returned",
      recipient: submission.employee,
      subject: "Returned: #{subject_label}",
      message: message,
      path: submitter_path
    )
  end

  def actor_text(level, actor)
    [ level, actor&.name.presence && "(#{actor.name})" ].compact.join(" ")
  end

  def kind_prefix
    case submission
    when ActionPlanSubmission then "action_plan"
    when AchievementSubmission then "achievement"
    else "project_summary"
    end
  end

  def subject_label
    case submission
    when ActionPlanSubmission
      "#{submission.plan_type_label} - #{submission.project_name}"
    when AchievementSubmission
      to = submission.to_name.presence && " (#{submission.to_name})"
      "Achievement #{submission.month.to_s.capitalize} - #{submission.project_name}#{to}"
    else
      "Project Summary (Rs. #{submission.total_amount.to_d.round(2).to_s("F")})"
    end
  end

  def approver_path(stage)
    case submission
    when ActionPlanSubmission then routes.action_plan_approvals_path(stage: stage)
    when AchievementSubmission then routes.achievement_approvals_path(stage: stage)
    else routes.project_summary_approvals_path
    end
  end

  def submitter_path
    case submission
    when ActionPlanSubmission then routes.action_plan_records_path
    when AchievementSubmission then routes.achievement_entry_records_path
    else routes.project_summary_records_path
    end
  end

  def routes
    Rails.application.routes.url_helpers
  end
end

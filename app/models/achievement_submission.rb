class AchievementSubmission < ApplicationRecord
  STATUSES = %w[pending approved returned].freeze
  STAGES = %w[vertical po coo director complete].freeze

  belongs_to :employee
  belongs_to :vertical_approver, class_name: "Employee", optional: true
  belongs_to :po_approver, class_name: "Employee", optional: true
  belongs_to :coo_approver, class_name: "Employee", optional: true
  belongs_to :director_approver, class_name: "Employee", optional: true
  has_many :achievement_submission_rows, dependent: :destroy
  has_many :action_plan_rows, through: :achievement_submission_rows

  validates :fco_id, :project_name, :po_id, :asa_theme_id, :month, :submitted_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :current_stage, inclusion: { in: STAGES }
  validates :month, inclusion: { in: ActionPlanRow::MONTH_COLUMNS }
  validate :approval_route_must_be_available

  scope :pending_for_stage, ->(stage) { where(status: "pending", current_stage: stage) }
  scope :active_for_rows, lambda { |row_ids, month|
    joins(:achievement_submission_rows)
      .where(status: %w[pending approved])
      .where(achievement_submission_rows: { action_plan_row_id: row_ids, month: month })
      .distinct
  }
  scope :locked_for_rows, lambda { |row_ids, month|
    joins(:achievement_submission_rows)
      .where.not(vertical_reviewed_at: nil)
      .where(status: %w[pending approved])
      .where(achievement_submission_rows: { action_plan_row_id: row_ids, month: month })
      .distinct
  }

  def self.coo_employee
    ActionPlanSubmission.coo_employee
  end

  def self.director_employee
    ActionPlanSubmission.director_employee
  end

  def self.stage_approver?(employee, stage)
    return false unless employee

    case stage.to_s
    when "vertical"
      ActionPlanVerticalMapping.for_employee(employee).exists? || where(vertical_approver: employee).exists?
    when "po"
      ProjectOwnership.for_employee(employee).exists? || where(po_approver: employee).exists?
    when "coo"
      ProjectOwnership.normalize_employee_code(employee.employee_code) == ActionPlanSubmission::COO_EMPLOYEE_CODE
    when "director"
      ProjectOwnership.normalize_employee_code(employee.employee_code) == ActionPlanSubmission::DIRECTOR_EMPLOYEE_CODE
    else
      false
    end
  end

  def self.stage_pending_count(employee, stage)
    return 0 unless employee
    return 0 if stage.to_s == "director"

    case stage.to_s
    when "vertical"
      pending_for_stage("vertical").where(vertical_approver: employee).count
    when "po"
      pending_for_stage("po").where(po_approver: employee).count
    when "coo"
      pending_for_stage("coo").where(coo_approver: employee).count
    else
      0
    end
  end

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def returned?
    status == "returned"
  end

  def locked_for_fco_edit?
    vertical_reviewed_at.present? && !returned?
  end

  def status_label
    return "Approved" if approved?
    return "Returned" if returned?

    {
      "vertical" => "Pending Vertical Approval",
      "po" => "Pending PO Approval",
      "coo" => "Pending COO Approval",
      "director" => "Approved (view only for Director)"
    }.fetch(current_stage, "Pending Approval")
  end

  def theme_ids
    asa_theme_id.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def theme_label
    ids = theme_ids
    return asa_theme_id if ids.size <= 1

    "#{ids.size} themes (#{ids.join(', ')})"
  end

  def stage_actor(stage)
    public_send("#{stage}_approver")&.name.presence || stage.to_s.titleize
  end

  private

  def approval_route_must_be_available
    return unless pending?

    if vertical_approver.blank?
      theme_hint = theme_ids.presence&.join(", ") || asa_theme_id
      errors.add(:base, "Vertical approver is not mapped for #{state_code} / ASA Theme #{theme_hint}.")
    end
    errors.add(:base, "Project Owner approver is not mapped for #{project_name}.") if po_approver.blank?
    errors.add(:base, "COO approver is not configured.") if coo_approver.blank?
  end
end

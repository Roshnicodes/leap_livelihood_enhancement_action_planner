class ActionPlanSubmission < ApplicationRecord
  COO_EMPLOYEE_CODE = ProjectOwnership.normalize_employee_code(ENV.fetch("ACTION_PLAN_COO_EMPLOYEE_CODE", "840")).freeze
  DIRECTOR_EMPLOYEE_CODE = ProjectOwnership.normalize_employee_code(ENV.fetch("ACTION_PLAN_DIRECTOR_EMPLOYEE_CODE", "002")).freeze
  PLAN_TYPES = %w[project vertical].freeze
  STATUSES = %w[pending approved returned].freeze
  STAGES = %w[po coo director complete].freeze

  belongs_to :employee
  belongs_to :project_ownership, optional: true
  belongs_to :po_approver, class_name: "Employee", optional: true
  belongs_to :coo_approver, class_name: "Employee", optional: true
  belongs_to :director_approver, class_name: "Employee", optional: true

  validates :po_id, :project_name, :submitted_at, presence: true
  validates :plan_type, inclusion: { in: PLAN_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :current_stage, inclusion: { in: STAGES }
  validate :approval_route_must_be_available

  before_validation :assign_approvers

  scope :pending_for_stage, ->(stage) { where(status: "pending", current_stage: stage) }

  def vertical_plan?
    plan_type == "vertical"
  end

  def plan_type_label
    vertical_plan? ? "Vertical Action Plan" : "Project Action Plan"
  end

  def scoped_action_plan_rows
    rows = ActionPlanRow.active_import.where(po_id: po_id)
    return rows.order(:id) unless vertical_plan?

    mappings = ActionPlanVerticalMapping.for_employee(employee).order(:state_code, :asa_theme_id).to_a
    rows = if mappings.present?
      rows.matching_action_plan_vertical_mappings(mappings)
    else
      rows.matching_verticals(employee&.action_plan_vertical_names)
    end

    rows.order(:id)
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

  def status_label
    return "Approved" if approved?
    return "Returned" if returned?

    {
      "po" => "Pending PO Approval",
      "coo" => "Pending COO Approval",
      "director" => "Pending Director Approval"
    }.fetch(current_stage, "Pending Approval")
  end

  def self.coo_employee
    Employee.find_by(employee_code: COO_EMPLOYEE_CODE)
  end

  def self.director_employee
    Employee.find_by(employee_code: DIRECTOR_EMPLOYEE_CODE)
  end

  def self.stage_approver?(employee, stage)
    return false unless employee

    case stage.to_s
    when "po"
      where(po_approver: employee).exists?
    when "coo"
      ProjectOwnership.normalize_employee_code(employee.employee_code) == COO_EMPLOYEE_CODE
    when "director"
      ProjectOwnership.normalize_employee_code(employee.employee_code) == DIRECTOR_EMPLOYEE_CODE
    else
      false
    end
  end

  def self.stage_pending_count(employee, stage)
    return 0 unless employee

    case stage.to_s
    when "po"
      pending_for_stage("po").where(po_approver: employee).count
    when "coo"
      pending_for_stage("coo").where(coo_approver: employee).count
    when "director"
      pending_for_stage("director").where(director_approver: employee).count
    else
      0
    end
  end

  private

  def assign_approvers
    ownership = project_ownership || ProjectOwnership.find_by(po_id: po_id, project_name: project_name)
    self.project_ownership ||= ownership
    self.po_approver ||= ownership&.owner_employee
    self.coo_approver ||= self.class.coo_employee
    self.director_approver ||= self.class.director_employee
  end

  def approval_route_must_be_available
    return unless pending?

    errors.add(:base, "Project Owner approver is not mapped for #{project_name}. Check Project_owner_id in the project ownership file.") if po_approver.blank?
    errors.add(:base, "COO approver is not configured.") if coo_approver.blank?
    errors.add(:base, "Director approver is not configured.") if director_approver.blank?
  end
end

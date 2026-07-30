class ProjectSummarySubmission < ApplicationRecord
  APPROVER_EMPLOYEE_CODE = ENV.fetch("PROJECT_SUMMARY_APPROVER_CODE", "002").freeze
  VIEWER_EMPLOYEE_CODE = ENV.fetch("PROJECT_SUMMARY_VIEWER_CODE", "644").freeze
  STATUSES = %w[pending approved returned].freeze

  belongs_to :employee
  belongs_to :approver, class_name: "Employee", optional: true
  has_many :project_summary_submission_items, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :total_amount, numericality: true

  before_validation :assign_default_approver, on: :create

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
    {
      "pending" => "Pending Approval",
      "approved" => "Approved",
      "returned" => "Returned"
    }.fetch(status, status.to_s.titleize)
  end

  def editable_by?(user)
    user&.employee_id == employee_id && !approved?
  end

  def self.approver_employee
    Employee.find_by(employee_code: APPROVER_EMPLOYEE_CODE)
  end

  def self.viewer_employee
    Employee.find_by(employee_code: VIEWER_EMPLOYEE_CODE)
  end

  def self.summary_approver?(employee)
    employee&.employee_code == APPROVER_EMPLOYEE_CODE
  end

  def self.summary_viewer?(employee)
    employee&.employee_code == VIEWER_EMPLOYEE_CODE
  end

  def self.summary_access?(employee)
    summary_approver?(employee) || summary_viewer?(employee)
  end

  private

  def assign_default_approver
    self.approver ||= self.class.approver_employee
  end
end

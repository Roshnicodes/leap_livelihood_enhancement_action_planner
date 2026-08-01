class ProjectSummarySubmission < ApplicationRecord
  FIRST_APPROVER_EMPLOYEE_CODE = ENV.fetch("PROJECT_SUMMARY_FIRST_APPROVER_CODE", "840").freeze
  FINAL_APPROVER_EMPLOYEE_CODE = ENV.fetch("PROJECT_SUMMARY_FINAL_APPROVER_CODE", "002").freeze
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
    first_approver_employee
  end

  def self.first_approver_employee
    Employee.find_by(employee_code: FIRST_APPROVER_EMPLOYEE_CODE)
  end

  def self.final_approver_employee
    Employee.find_by(employee_code: FINAL_APPROVER_EMPLOYEE_CODE)
  end

  def self.viewer_employee
    Employee.find_by(employee_code: VIEWER_EMPLOYEE_CODE)
  end

  def self.summary_approver?(employee)
    [ FIRST_APPROVER_EMPLOYEE_CODE, FINAL_APPROVER_EMPLOYEE_CODE ].include?(employee&.employee_code)
  end

  def self.summary_viewer?(employee)
    employee&.employee_code == VIEWER_EMPLOYEE_CODE
  end

  def self.summary_access?(employee)
    summary_approver?(employee) || summary_viewer?(employee)
  end

  private

  def assign_default_approver
    self.approver ||= self.class.first_approver_employee
  end
end

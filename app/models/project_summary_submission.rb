class ProjectSummarySubmission < ApplicationRecord
  FIRST_APPROVER_EMPLOYEE_CODE = ENV.fetch("PROJECT_SUMMARY_FIRST_APPROVER_CODE", "840").freeze
  FINAL_APPROVER_EMPLOYEE_CODE = ENV.fetch("PROJECT_SUMMARY_FINAL_APPROVER_CODE", "002").freeze
  STATUSES = %w[pending approved returned].freeze

  belongs_to :employee
  belongs_to :approver, class_name: "Employee", optional: true
  belongs_to :first_approver, class_name: "Employee", optional: true
  has_many :project_summary_submission_items, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :total_amount, numericality: true

  before_validation :assign_default_approver, on: :create
  before_validation :assign_final_approver_after_first_approval

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

  def apply_to_pb!
    return unless approved?
    return if pb_applied_at.present?

    transaction do
      project_summary_submission_items.find_each do |item|
        apply_item_to_bli_activities!(item)
      end

      update!(pb_applied_at: Time.current)
    end

    PbSourceFileUpdater.update_latest!(self.class.approved_items_for_pb_download)
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

  def self.summary_approver?(employee)
    [ FIRST_APPROVER_EMPLOYEE_CODE, FINAL_APPROVER_EMPLOYEE_CODE ].include?(employee&.employee_code)
  end

  def self.summary_access?(employee)
    summary_approver?(employee)
  end

  def self.approved_items_for_pb_download
    where(status: "approved")
      .includes(:project_summary_submission_items)
      .flat_map(&:project_summary_submission_items)
  end

  private

  def assign_default_approver
    self.approver ||= self.class.first_approver_employee
  end

  def assign_final_approver_after_first_approval
    return unless pending? && first_approver_id.present?

    self.approver ||= self.class.final_approver_employee
    self.approver = self.class.final_approver_employee if approver_id == first_approver_id
  end

  def apply_item_to_bli_activities!(item)
    activities = BliActivity
      .where(project_name: item.project_name, activity_name: item.activity_name, vertical_name: item.vertical_name)
      .order(:id)
      .to_a
    return [] if activities.empty?

    target_total = item.changed_total.to_d
    current_total = activities.sum { |activity| activity.allocated_fund.to_d }
    running_total = BigDecimal("0")

    activities.each_with_index do |activity, index|
      new_amount = if index == activities.size - 1
        target_total - running_total
      elsif current_total.zero?
        (target_total / activities.size).round(2)
      else
        (target_total * activity.allocated_fund.to_d / current_total).round(2)
      end

      running_total += new_amount
      activity.update!(
        allocated_fund: new_amount,
        remaining_fund: new_amount - activity.utilised_fund.to_d
      )
    end

    activities
  end
end

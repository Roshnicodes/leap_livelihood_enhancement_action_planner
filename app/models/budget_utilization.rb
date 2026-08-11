class BudgetUtilization < ApplicationRecord
  FINANCE_EMPLOYEE_CODE = "1621".freeze
  STATUSES = %w[draft submitted].freeze
  MONTH_KEYS = VerticalPercent::MONTH_COLUMNS.map(&:to_s).freeze
  QUARTERS = {
    "Q1" => %w[apr may jun],
    "Q2" => %w[jul aug sep],
    "Q3" => %w[oct nov dec],
    "Q4" => %w[jan feb mar]
  }.freeze

  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :submitted_by, class_name: "User", optional: true

  validates :project_name, :activity_name, :vertical_name, :month, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :month, inclusion: { in: MONTH_KEYS }
  validates :utilized_amount, :planned_amount, numericality: { greater_than_or_equal_to: 0 }

  scope :with_single_bli_code, -> {
    where.not(bli_code: [ nil, "" ]).where("bli_code NOT LIKE ?", "%,%")
  }
  scope :submitted, -> { where(status: "submitted") }
  scope :draft, -> { where(status: "draft") }

  def self.finance_user?(user)
    return false if user.blank? || user.admin?

    ProjectOwnership.normalize_employee_code(user.employee&.employee_code) == FINANCE_EMPLOYEE_CODE
  end

  def submitted?
    status == "submitted"
  end

  def draft?
    status == "draft"
  end

  # Months Apr..latest saved month, with quarter markers after Jun/Sep/Dec/Mar.
  def self.report_columns_through(latest_month)
    index = MONTH_KEYS.index(latest_month.to_s)
    return [] unless index

    visible = MONTH_KEYS[0..index]
    columns = []

    visible.each do |month|
      columns << { type: :month, key: month, label: month.capitalize }
      quarter = QUARTERS.find { |_label, months| months.last == month }
      next unless quarter

      label, months = quarter
      next unless months.all? { |candidate| visible.include?(candidate) }

      columns << { type: :quarter, key: label, label: label, months: months }
    end

    columns
  end

  def self.latest_saved_month(project_name: nil)
    scope = submitted
    scope = scope.where(project_name: project_name) if project_name.present?
    months = scope.distinct.pluck(:month)
    return if months.blank?

    months.max_by { |month| MONTH_KEYS.index(month.to_s) || -1 }
  end
end

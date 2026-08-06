class ActionPlanVerticalMapping < ApplicationRecord
  belongs_to :employee, optional: true

  before_validation :normalize_codes

  validates :employee_code, :state_code, :asa_theme_id, presence: true
  validates :asa_theme_id, uniqueness: { scope: [ :employee_code, :state_code ] }

  scope :for_employee, lambda { |employee|
    if employee.blank?
      none
    else
      where(employee: employee).or(where(employee_code: employee.employee_code))
    end
  }

  def label
    [ state_code, asa_theme.presence || asa_theme_id ].compact_blank.join(" / ")
  end

  # Mapped employees must be able to sign in to reach their Vertical Action Plan.
  def self.enable_employee_logins!
    employees = Employee.where(employee_code: distinct.pluck(:employee_code))

    employees.find_each do |employee|
      employee.update!(active: true) unless employee.active?
      User.ensure_login_for(employee)
    end

    employees.count
  end

  private

  def normalize_codes
    self.employee_code = self.class.normalize_code(employee_code)
    self.state_code = state_code.to_s.squish.upcase
    self.asa_theme_id = ActionPlanRow.format_decimal_string(asa_theme_id)
    self.asa_theme = asa_theme.to_s.squish.presence
  end

  def self.normalize_code(value)
    ActionPlanRow.format_decimal_string(value.to_s).squish
  end
end

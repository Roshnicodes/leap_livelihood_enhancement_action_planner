class EmployeeVerticalMapping < ApplicationRecord
  belongs_to :employee
  belongs_to :vertical_percent

  validates :vertical_percent_id, uniqueness: { scope: :employee_id }

  scope :active, -> { where(active: true) }
  scope :disabled, -> { where(active: false) }
end

class EmployeeVerticalMapping < ApplicationRecord
  belongs_to :employee
  belongs_to :vertical_percent

  validates :vertical_percent_id, uniqueness: { scope: :employee_id }
end

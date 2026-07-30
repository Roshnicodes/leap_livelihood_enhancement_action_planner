class VerticalPercent < ApplicationRecord
  MONTH_COLUMNS = %i[apr may jun jul aug sep oct nov dec jan feb mar].freeze

  has_many :employee_vertical_mappings, dependent: :destroy
  has_many :employees, through: :employee_vertical_mappings

  validates :vertical_name, presence: true, uniqueness: true
  validates :total, *MONTH_COLUMNS, numericality: true
end

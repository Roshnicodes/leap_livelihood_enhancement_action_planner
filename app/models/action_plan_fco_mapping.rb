class ActionPlanFcoMapping < ApplicationRecord
  belongs_to :employee

  validates :employee_code, :fco_id, :fco_name, presence: true
  validates :fco_id, uniqueness: { scope: :employee_id }

  before_validation :normalize_text

  scope :for_employee, ->(employee) { where(employee: employee) }

  def self.ensure_for_employee(employee)
    return none if employee.blank?

    for_employee(employee)
  end

  def self.fco_staff?(employee)
    for_employee(employee).exists?
  end

  def self.import_file!(path)
    available_fcos = action_plan_fcos.index_by { |fco| fco[:fco_id] }
    result = { imported: 0, skipped: [] }

    transaction do
      SpreadsheetRows.read(path, sheet: :first).each_with_index do |row, index|
        row_number = index + 2
        employee_code = normalize_code(value(row, "Employee Code", "Employee ID", "Emp ID", "emp_id"))
        fco_id = ActionPlanText.normalize(value(row, "FCO ID", "FCO_ID", "User ID", "User_Id")).to_s
        fco_name = ActionPlanText.normalize(value(row, "FCO Name", "FCO_Name", "User Name", "User_Name")).to_s

        if employee_code.blank? || fco_id.blank?
          result[:skipped] << "Row #{row_number}: Employee Code and FCO ID are required"
          next
        end

        employee = Employee.find_by(employee_code: employee_code)
        unless employee
          result[:skipped] << "Row #{row_number}: Employee #{employee_code} not found"
          next
        end

        fco = available_fcos[fco_id]
        if fco.blank? && fco_name.blank?
          result[:skipped] << "Row #{row_number}: FCO #{fco_id} not found in active Action Plan"
          next
        end

        mapping = find_or_initialize_by(employee: employee, fco_id: fco_id)
        mapping.employee_code = employee.employee_code
        mapping.fco_name = fco&.fetch(:fco_name) || fco_name
        mapping.save!
        result[:imported] += 1
      end
    end

    result
  end

  def self.action_plan_fcos
    ActionPlanRow.active_import
      .where.not(user_id: [ nil, "" ])
      .distinct
      .order(:user_name, :user_id)
      .pluck(:user_id, :user_name)
      .map { |fco_id, fco_name| { fco_id: fco_id.to_s.squish, fco_name: fco_name.to_s.squish } }
  end

  private

  def self.value(row, *headers)
    normalized = row.transform_keys { |key| key.to_s.squish.downcase }
    raw = headers.lazy.filter_map { |header| normalized[header.to_s.squish.downcase] }.first
    text = ActionPlanText.normalize(raw)
    text == "NULL" ? nil : text
  end

  def self.normalize_code(value)
    ActionPlanRow.format_decimal_string(ActionPlanText.normalize(value).to_s)
  end

  def normalize_text
    self.employee_code = self.class.normalize_code(employee_code)
    self.fco_id = self.class.normalize_code(fco_id)
    self.fco_name = fco_name.to_s.squish
  end
end

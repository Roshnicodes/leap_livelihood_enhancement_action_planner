class ActionPlanFcoMapping < ApplicationRecord
  belongs_to :employee

  validates :employee_code, :fco_id, :fco_name, presence: true
  validates :fco_id, uniqueness: { scope: :employee_id }

  before_validation :normalize_text

  scope :active, -> { where(active: true) }
  scope :disabled, -> { where(active: false) }
  scope :for_employee, ->(employee) { active.where(employee: employee) }

  def self.ensure_for_employee(employee)
    return none if employee.blank?

    for_employee(employee)
  end

  def self.fco_staff?(employee)
    for_employee(employee).exists?
  end

  def self.import_file!(path)
    available_fcos = action_plan_fcos_by_id
    result = { imported: 0, skipped: [] }

    transaction do
      SpreadsheetRows.read(path, sheet: :first, header_match: [ "Employee Code", "FCO ID" ]).each_with_index do |row, index|
        row_number = index + 1
        employee_code = normalize_code(value(row, "Employee Code", "Employee ID", "Emp ID", "emp_id"))
        fco_id = normalize_fco_id(value(row, "FCO ID", "FCO_ID", "User ID", "User_Id"))
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

        mapping = find_or_initialize_by(employee: employee, fco_id: fco&.fetch(:fco_id) || fco_id)
        mapping.employee_code = employee.employee_code
        mapping.fco_name = fco&.fetch(:fco_name) || fco_name
        mapping.active = true
        mapping.save!
        enable_login_for!(employee)
        result[:imported] += 1
      end
    end

    result
  end

  def self.enable_login_for!(employee)
    return if employee.blank?

    employee.update!(active: true) unless employee.active?
    User.ensure_login_for(employee)
  end

  def self.action_plan_fcos
    grouped = Hash.new do |hash, fco_id|
      hash[fco_id] = {
        fco_id: fco_id,
        fco_ids: ActionPlanFcoGroup.ids_for(fco_id),
        names: Hash.new(0)
      }
    end

    ActionPlanRow.active_import
      .where.not(user_id: [ nil, "" ])
      .group(:user_id, :user_name)
      .count
      .each do |(raw_fco_id, raw_fco_name), count|
        fco_id = normalize_fco_id(raw_fco_id)
        fco_name = raw_fco_name.to_s.squish

        grouped[fco_id][:names][fco_name] += count if fco_name.present?
      end

    grouped.values
      .map do |fco|
        {
          fco_id: fco[:fco_id],
          fco_name: grouped_fco_name(fco[:fco_id], fco[:names]),
          fco_ids: fco[:fco_ids]
        }
      end
      .sort_by { |fco| [ fco[:fco_name].to_s.downcase, fco[:fco_id].to_s ] }
  end

  def self.action_plan_fcos_by_id
    action_plan_fcos.each_with_object({}) do |fco, lookup|
      Array(fco[:fco_ids]).each { |fco_id| lookup[normalize_code(fco_id)] = fco }
      lookup[fco[:fco_id]] = fco
    end
  end

  def self.normalize_fco_id(value)
    ActionPlanFcoGroup.canonical_id(normalize_code(value))
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

  def self.grouped_fco_name(fco_id, names)
    ActionPlanFcoGroup.name_for(fco_id).presence ||
      names.max_by { |name, count| [ count, name ] }&.first ||
      fco_id
  end

  def normalize_text
    self.employee_code = self.class.normalize_code(employee_code)
    self.fco_id = self.class.normalize_fco_id(fco_id)
    self.fco_name = ActionPlanFcoGroup.name_for(fco_id, fco_name).presence || fco_name.to_s.squish
  end
end

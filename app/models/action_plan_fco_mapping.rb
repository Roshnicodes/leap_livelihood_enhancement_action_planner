class ActionPlanFcoMapping < ApplicationRecord
  belongs_to :employee

  validates :employee_code, :fco_id, :fco_name, presence: true
  validates :fco_id, uniqueness: { scope: :employee_id }

  before_validation :normalize_text

  scope :for_employee, ->(employee) { where(employee: employee) }

  def self.ensure_for_employee(employee)
    return none if employee.blank?
    return for_employee(employee) if for_employee(employee).exists?

    matches_for_employee(employee).each do |match|
      find_or_create_by!(employee: employee, fco_id: match[:fco_id]) do |mapping|
        mapping.employee_code = employee.employee_code
        mapping.fco_name = match[:fco_name]
      end
    end

    for_employee(employee)
  end

  def self.fco_staff?(employee)
    employee_fco_tokens(employee).present?
  end

  def self.matches_for_employee(employee)
    employee_tokens = employee_fco_tokens(employee)
    return [] if employee_tokens.blank?

    action_plan_fcos.filter_map do |fco|
      fco_tokens = fco_name_tokens(fco[:fco_name])
      next unless token_match?(employee_tokens, fco_tokens)

      fco
    end
  end

  def self.action_plan_fcos
    ActionPlanRow.active_import
      .where.not(user_id: [ nil, "" ])
      .distinct
      .order(:user_name, :user_id)
      .pluck(:user_id, :user_name)
      .map { |fco_id, fco_name| { fco_id: fco_id.to_s.squish, fco_name: fco_name.to_s.squish } }
  end

  def self.employee_fco_tokens(employee)
    return [] if employee.blank?

    fields = [
      employee.branch,
      employee.sub_branch,
      employee.office_name,
      employee.email,
      employee.designation
    ].compact_blank
    text = fields.join(" ").downcase
    return [] unless text.include?("fco")

    tokens = []
    text.scan(/fco\s*[-_. ]+\s*([a-z]+)/) { |match| tokens << match.first }
    text.scan(/fco[._-]([a-z]+)/) { |match| tokens << match.first }
    text.scan(/pmu[._-]([a-z]+)/) { |match| tokens << match.first }
    normalize_tokens(tokens)
  end

  def self.fco_name_tokens(name)
    normalize_tokens(name.to_s.downcase.gsub(/\bfco\b/i, " ").split(/[^a-z0-9]+/))
  end

  def self.normalize_tokens(tokens)
    Array(tokens)
      .map { |token| token.to_s.downcase.gsub(/[^a-z0-9]/, "") }
      .reject { |token| token.blank? || token.in?(%w[fco to sub team office direct reporting cisspo mp]) }
      .flat_map { |token| [ token, token.gsub("h", "") ] }
      .uniq
  end

  def self.token_match?(employee_tokens, fco_tokens)
    employee_tokens.any? do |employee_token|
      fco_tokens.any? do |fco_token|
        employee_token == fco_token ||
          (employee_token.length >= 5 && fco_token.include?(employee_token)) ||
          (fco_token.length >= 5 && employee_token.include?(fco_token))
      end
    end
  end

  private

  def normalize_text
    self.employee_code = employee_code.to_s.squish
    self.fco_id = fco_id.to_s.squish
    self.fco_name = fco_name.to_s.squish
  end
end

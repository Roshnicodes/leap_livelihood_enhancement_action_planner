class ProjectOwnership < ApplicationRecord
  has_many :action_plan_submissions, dependent: :nullify

  validates :po_id, :project_name, presence: true

  scope :for_employee, lambda { |employee|
    if employee.blank?
      none
    else
      code = normalize_employee_code(employee.employee_code)
      code_candidates = [ code, employee.employee_code.to_s.squish, ("#{code}.0" if code.match?(/\A\d+\z/)) ].compact.uniq
      email = employee.email.to_s.squish.downcase
      name = employee.name.to_s.squish.downcase

      scope = where(project_owner_id: code_candidates)
      scope = scope.or(where("LOWER(email_id) = ?", email)) if email.present?
      scope = scope.or(where("LOWER(po_name) = ?", name)) if name.present?
      scope
    end
  }

  def self.action_plan_project_names_for(employee)
    for_employee(employee).order(:po_id).filter_map do |ownership|
      resolve_action_plan_project_name(ownership)
    end.uniq.sort
  end

  def self.owned?(employee, project_name)
    action_plan_project_names_for(employee).include?(project_name.to_s)
  end

  def self.find_owned_for(employee, project_name: nil, po_id: nil)
    scope = for_employee(employee)
    return scope.find_by(po_id: po_id) if po_id.present?
    return scope.find_by(project_name: project_name) if project_name.present?

    nil
  end

  def self.resolve_action_plan_project_name(ownership)
    by_po = ActionPlanRow.active_import.where(po_id: ownership.po_id).distinct.order(:project_name).pluck(:project_name)
    return by_po.first if by_po.one?
    return by_po.first if by_po.any?

    by_exact = ActionPlanRow.active_import.find_by(project_name: ownership.project_name)&.project_name
    return by_exact if by_exact.present?

    normalized = normalize_project_key(ownership.project_name)
    ActionPlanRow.active_import.distinct.pluck(:project_name).find do |name|
      normalize_project_key(name) == normalized
    end || ownership.project_name
  end

  def self.normalize_project_key(name)
    name.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end

  def self.normalize_employee_code(value)
    text = value.to_s.squish
    return text if text.match?(/\A0\d+\z/)

    ActionPlanRow.format_decimal_string(text)
  end

  def owner_employee
    normalized_code = self.class.normalize_employee_code(project_owner_id)
    normalized_email = email_id.to_s.squish.downcase

    Employee.find_by(employee_code: normalized_code.presence) ||
      Employee.find_by(employee_code: project_owner_id.to_s.squish.presence) ||
      Employee.where("LOWER(email) = ?", normalized_email).first ||
      Employee.where("LOWER(name) = ?", po_name.to_s.squish.downcase).first
  end
end

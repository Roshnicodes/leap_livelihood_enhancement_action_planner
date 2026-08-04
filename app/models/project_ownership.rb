class ProjectOwnership < ApplicationRecord
  has_many :action_plan_submissions, dependent: :nullify

  validates :po_id, :project_name, presence: true

  scope :for_employee, lambda { |employee|
    if employee.blank?
      none
    else
      code = employee.employee_code.to_s
      email = employee.email.to_s.squish.downcase
      name = employee.name.to_s.squish.downcase

      where(project_owner_id: code)
        .or(where("LOWER(email_id) = ?", email))
        .or(where("LOWER(po_name) = ?", name))
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

  def owner_employee
    Employee.find_by(employee_code: project_owner_id.presence) ||
      Employee.find_by(email: email_id.to_s.squish.presence) ||
      Employee.where("LOWER(name) = ?", po_name.to_s.squish.downcase).first
  end
end

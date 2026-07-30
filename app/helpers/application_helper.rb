module ApplicationHelper
  def approval_actor_label(employee, fallback = "Approver")
    return fallback if employee.blank?
    return "you" if current_user&.employee&.id == employee.id

    employee.name.presence || fallback
  end
end

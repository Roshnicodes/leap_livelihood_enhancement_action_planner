module ApplicationHelper
  CURRENCY_OPTIONS = { unit: "₹", precision: 0 }.freeze

  def currency(amount)
    number_to_currency(amount, **CURRENCY_OPTIONS)
  end

  def currency_input_value(amount)
    number_with_precision(amount, precision: 0, delimiter: "", separator: ".")
  end

  def rounded_month_total(month_amounts)
    VerticalPercent::MONTH_COLUMNS.sum { |month| month_amounts[month].to_d.round }
  end

  def approval_actor_label(employee, fallback = "Approver")
    return fallback if employee.blank?
    return "you" if current_user&.employee&.id == employee.id

    employee.name.presence || fallback
  end
end

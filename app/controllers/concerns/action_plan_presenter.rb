module ActionPlanPresenter
  extend ActiveSupport::Concern

  private

  def owned_project_options
    ProjectOwnership.action_plan_project_names_for(current_user.employee)
  end

  def vertical_project_options
    mappings = action_plan_vertical_mappings
    if mappings.present?
      return ActionPlanRow
        .active_import
        .matching_action_plan_vertical_mappings(mappings)
        .distinct
        .order(:project_name)
        .pluck(:project_name)
        .sort
    end

    vertical_names = action_plan_vertical_names
    return [] if vertical_names.empty?

    ActionPlanRow
      .active_import
      .distinct
      .order(:project_name)
      .pluck(:project_name, :po_id)
      .uniq { |(_, po_id)| po_id }
      .select { |(_project_name, po_id)| ActionPlanRow.active_import.where(po_id: po_id).matching_verticals(vertical_names).exists? }
      .map(&:first)
      .sort
  end

  def action_plan_vertical_names
    current_user.employee.action_plan_vertical_names
  end

  def action_plan_vertical_mappings
    ActionPlanVerticalMapping.for_employee(current_user.employee).order(:state_code, :asa_theme_id).to_a
  end

  def project_ownership_for(project_name)
    return if project_name.blank?

    row = ActionPlanRow.active_import.find_by(project_name: project_name)
    ProjectOwnership.find_owned_for(current_user.employee, project_name: project_name, po_id: row&.po_id)
  end

  def action_plan_rows_for(project_name, vertical_filter: false)
    return ActionPlanRow.none if project_name.blank?

    po_id = project_po_id_for(project_name)
    return ActionPlanRow.none if po_id.blank?

    rows = ActionPlanRow.active_import.where(po_id: po_id)
    if vertical_filter
      mappings = action_plan_vertical_mappings
      rows = mappings.present? ? rows.matching_action_plan_vertical_mappings(mappings) : rows.matching_verticals(action_plan_vertical_names)
    end
    rows.order(:id)
  end

  def project_options_for_viewer
    return ActionPlanRow.active_import.distinct.order(:project_name).pluck(:project_name) if current_user.admin?

    owned_project_options
  end

  def project_po_id_for(project_name)
    project_ownership_for(project_name)&.po_id ||
      ActionPlanRow.active_import.where(project_name: project_name).pick(:po_id)
  end

  def project_names_match?(left, right)
    ProjectOwnership.normalize_project_key(left) == ProjectOwnership.normalize_project_key(right)
  end
end

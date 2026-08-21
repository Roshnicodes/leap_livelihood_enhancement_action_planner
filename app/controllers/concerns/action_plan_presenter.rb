module ActionPlanPresenter
  extend ActiveSupport::Concern

  private

  def owned_project_options
    ProjectOwnership.action_plan_project_names_for(current_user.employee)
  end

  def vertical_project_options
    return all_project_options if current_user.admin?

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
    current_user.employee&.action_plan_vertical_names || []
  end

  def action_plan_vertical_mappings
    ActionPlanVerticalMapping.for_employee(current_user.employee).order(:state_code, :asa_theme_id).to_a
  end

  def project_ownership_for(project_name)
    return if project_name.blank?

    row = ActionPlanRow.active_import.find_by(project_name: project_name)
    return ProjectOwnership.find_by(po_id: row&.po_id, project_name: project_name) ||
      ProjectOwnership.find_by(po_id: row&.po_id) ||
      ProjectOwnership.find_by(project_name: project_name) if current_user.admin?

    ProjectOwnership.find_owned_for(current_user.employee, project_name: project_name, po_id: row&.po_id)
  end

  def action_plan_rows_for(project_name, vertical_filter: false, fco_id: nil, to_id: nil)
    return ActionPlanRow.none if project_name.blank?

    rows = if project_name == "all"
      ActionPlanRow.active_import.where(project_name: project_options_for_action_plan_scope(vertical_filter: vertical_filter))
    else
      po_id = project_po_id_for(project_name)
      return ActionPlanRow.none if po_id.blank?

      ActionPlanRow.active_import.where(po_id: po_id)
    end

    if vertical_filter && !current_user.admin?
      mappings = action_plan_vertical_mappings
      rows = mappings.present? ? rows.matching_action_plan_vertical_mappings(mappings) : rows.matching_verticals(action_plan_vertical_names)
    elsif project_name != "all" && fco_scoped_action_plan?(project_name)
      rows = rows.where(user_id: action_plan_fco_ids)
    end

    rows = rows.where(user_id: fco_filter_ids(fco_id)) if fco_id.present?
    rows = rows.where(to_id: to_id) if to_id.present?

    rows.order(:id)
  end

  def action_plan_filter_options(project_name, label_attribute, value_attribute, fco_id: nil)
    rows = action_plan_rows_for(project_name.presence || "all", vertical_filter: controller_name == "vertical_action_plans")
    rows = rows.where(user_id: fco_filter_ids(fco_id)) if fco_id.present?

    return fco_filter_options_for(rows) if value_attribute.to_sym == :user_id

    rows
      .where.not(value_attribute => [ nil, "" ])
      .distinct
      .reorder(label_attribute, value_attribute)
      .pluck(label_attribute, value_attribute)
      .map { |label, value| [ label.presence || value.to_s, value.to_s ] }
  end

  def project_options_for_viewer
    return all_project_options if current_user.admin?

    (owned_project_options + fco_project_options).uniq.sort
  end

  def fco_project_options
    return [] unless current_user.employee&.action_plan_fco?

    ActionPlanRow
      .active_import
      .where(user_id: action_plan_fco_ids)
      .where.not(project_name: [ nil, "" ])
      .distinct
      .order(:project_name)
      .pluck(:project_name)
  end

  def action_plan_fco_ids
    @action_plan_fco_ids ||= ActionPlanFcoMapping.ensure_for_employee(current_user.employee).pluck(:fco_id)
  end

  def fco_filter_ids(fco_id)
    fco_id.to_s.split(",").map(&:squish).compact_blank
  end

  def fco_filter_options_for(rows)
    options = rows
      .where.not(user_id: [ nil, "" ])
      .distinct
      .reorder(:user_name, :user_id)
      .pluck(:user_name, :user_id)
      .map { |label, value| [ label.presence || value.to_s, value.to_s ] }

    return options unless pritesh_jain_fco_grouping?

    grouped_ids = %w[16 17]
    grouped_options = options.select { |(_label, value)| value.in?(grouped_ids) }
    return options if grouped_options.empty?

    remaining_options = options.reject { |(_label, value)| value.in?(grouped_ids) }
    ([ [ "Jobat - FCO", grouped_ids.join(",") ] ] + remaining_options).sort_by(&:first)
  end

  def pritesh_jain_fco_grouping?
    current_user.employee&.employee_code.to_s == "25"
  end

  # FCO viewers who do not own the project only see their own FCO target rows.
  def fco_scoped_action_plan?(project_name)
    return false if current_user.admin?
    return false unless current_user.employee&.action_plan_fco?
    return false if ProjectOwnership.owned?(current_user.employee, project_name)

    true
  end

  def all_project_options
    ActionPlanRow.active_import.distinct.order(:project_name).pluck(:project_name)
  end

  def project_options_for_action_plan_scope(vertical_filter:)
    if vertical_filter
      vertical_project_options
    else
      project_options_for_viewer
    end
  end

  def project_po_id_for(project_name)
    project_ownership_for(project_name)&.po_id ||
      ActionPlanRow.active_import.where(project_name: project_name).pick(:po_id)
  end

  def project_names_match?(left, right)
    ProjectOwnership.normalize_project_key(left) == ProjectOwnership.normalize_project_key(right)
  end
end

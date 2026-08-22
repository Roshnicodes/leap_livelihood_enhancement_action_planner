module ActionPlanPresenter
  extend ActiveSupport::Concern

  PERIOD_FILTER_OPTIONS = [
    [ "Monthly", "monthly" ],
    [ "1st Quarter (Apr-Jun)", "quarter_1" ],
    [ "2nd Quarter (Jul-Sep)", "quarter_2" ],
    [ "3rd Quarter (Oct-Dec)", "quarter_3" ],
    [ "4th Quarter (Jan-Mar)", "quarter_4" ],
    [ "Half Yearly", "half_yearly" ],
    [ "Yearly", "yearly" ],
    [ "Till Month", "till_month" ]
  ].freeze
  QUARTER_MONTHS = {
    "quarter_1" => %w[apr may jun],
    "quarter_2" => %w[jul aug sep],
    "quarter_3" => %w[oct nov dec],
    "quarter_4" => %w[jan feb mar]
  }.freeze

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

  def action_plan_rows_for(project_name, vertical_filter: false, fco_id: nil, to_id: nil, state_code: nil, vertical_name: nil)
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
    elsif fco_scoped_action_plan?(project_name)
      rows = rows.where(user_id: action_plan_fco_ids)
    end

    rows = rows.where(user_id: fco_filter_ids(fco_id)) if fco_id.present?
    rows = rows.where(to_id: to_id) if to_id.present?
    rows = rows.where(statte: state_code) if state_code.present?
    rows = rows.where(asa_theme: vertical_name) if vertical_name.present?

    rows.order(:id)
  end

  def action_plan_filter_options(project_name, label_attribute, value_attribute, fco_id: nil, to_id: nil, state_code: nil, vertical_name: nil)
    rows = action_plan_rows_for(
      project_name.presence || "all",
      vertical_filter: controller_name == "vertical_action_plans",
      state_code: state_code,
      vertical_name: vertical_name
    )
    rows = rows.where(user_id: fco_filter_ids(fco_id)) if fco_id.present?
    rows = rows.where(to_id: to_id) if to_id.present?

    return fco_filter_options_for(rows) if value_attribute.to_sym == :user_id

    rows
      .where.not(value_attribute => [ nil, "" ])
      .distinct
      .reorder(label_attribute, value_attribute)
      .pluck(label_attribute, value_attribute)
      .map { |label, value| [ label.presence || value.to_s, value.to_s ] }
  end

  def action_plan_period_options
    PERIOD_FILTER_OPTIONS
  end

  def selected_period
    params[:period].to_s.presence_in(PERIOD_FILTER_OPTIONS.map(&:last)) || "yearly"
  end

  def selected_period_month
    params[:period_month].to_s.presence_in(ActionPlanRow::MONTH_COLUMNS) || current_action_plan_month
  end

  def action_plan_month_pairs_for(period, month)
    months = period_months(period, month)
    ActionPlanRow::MONTH_DISPLAY_PAIRS.select { |pair| pair[:target_column].in?(months) }
  end

  def period_months(period, month)
    month = month.presence_in(ActionPlanRow::MONTH_COLUMNS) || current_action_plan_month
    index = ActionPlanRow::MONTH_COLUMNS.index(month) || 0

    case period
    when "monthly"
      [ month ]
    when *QUARTER_MONTHS.keys
      QUARTER_MONTHS.fetch(period)
    when "quarterly"
      start_index = (index / 3) * 3
      ActionPlanRow::MONTH_COLUMNS[start_index, 3]
    when "half_yearly"
      start_index = index < 6 ? 0 : 6
      ActionPlanRow::MONTH_COLUMNS[start_index, 6]
    when "till_month"
      ActionPlanRow::MONTH_COLUMNS[0..index]
    else
      ActionPlanRow::MONTH_COLUMNS
    end
  end

  def current_action_plan_month
    Date.current.strftime("%b").downcase.presence_in(ActionPlanRow::MONTH_COLUMNS) || "apr"
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
    fco_id.to_s.split(",").flat_map { |id| ActionPlanFcoGroup.ids_for(id) }.compact_blank.uniq
  end

  def fco_filter_options_for(rows)
    options = rows
      .where.not(user_id: [ nil, "" ])
      .distinct
      .reorder(:user_name, :user_id)
      .pluck(:user_name, :user_id)
      .map { |label, value| [ label.presence || value.to_s, value.to_s ] }

    ActionPlanFcoGroup.group_options(options)
  end

  # FCO viewers who do not own the project only see their own FCO target rows.
  def fco_scoped_action_plan?(project_name)
    return false if current_user.admin?
    return false unless current_user.employee&.action_plan_fco?

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

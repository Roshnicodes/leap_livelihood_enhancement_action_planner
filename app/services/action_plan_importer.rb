class ActionPlanImporter
  MONTH_COLUMNS = %w[apr may jun jul aug sep oct nov dec jan feb mar].freeze
  TARGET_MONTH_COLUMNS = MONTH_COLUMNS.map { |month| "#{month}_t" }.freeze

  def initialize(project_file: nil, action_plan_file: nil, vertical_mapping_file: nil)
    @project_file = project_file
    @action_plan_file = action_plan_file
    @vertical_mapping_file = vertical_mapping_file
  end

  def import!
    result = { project_ownerships: nil, action_plan_rows: nil, vertical_mappings: nil }

    ActiveRecord::Base.transaction do
      result[:project_ownerships] = import_project_ownerships! if @project_file.present?
      result[:action_plan_rows] = import_action_plan_rows! if @action_plan_file.present?
      result[:vertical_mappings] = import_vertical_mappings! if @vertical_mapping_file.present?
    end

    result
  end

  private

  def import_project_ownerships!
    rows = SpreadsheetRows.read(file_path(@project_file)).filter_map do |row|
      po_id = value(row, "PO_ID")
      project_name = value(row, "Project")
      next if po_id.blank? || project_name.blank?

      {
        po_id: po_id,
        project_name: project_name,
        project_owner_id: value(row, "Project_owner_id"),
        po_name: value(row, "PO_Name"),
        email_id: value(row, "Email_Id"),
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    ProjectOwnership.delete_all
    ProjectOwnership.insert_all!(rows) if rows.any?
    rows.size
  end

  def import_action_plan_rows!
    imported_at = Time.current

    rows = SpreadsheetRows.read(file_path(@action_plan_file), sheet: :first).filter_map do |row|
      po_id = value(row, "PO_ID")
      project_name = value(row, "Project")
      next if po_id.blank? || project_name.blank?

      month_values = MONTH_COLUMNS.index_with do |month|
        integer_value(row, month.capitalize, "#{month.capitalize} Target")
      end
      target_values = TARGET_MONTH_COLUMNS.index_with do |month|
        label = month.delete_suffix("_t").capitalize
        integer_value(row, "#{label}_T", "#{label} Achievement", "#{label}_Achievement")
      end

      {
        id_new: value(row, "ID_New", "ID_NEW", "Id_New"),
        statte: value(row, "Statte", "State", "STATE"),
        po_id: po_id,
        project_name: project_name,
        project_id: value(row, "Project_ID", "Project ID").presence || po_id,
        project_owner: value(row, "Project_Owner"),
        user_id: value(row, "User_Id"),
        user_name: value(row, "User_Name"),
        to_id: value(row, "TO_ID"),
        to_name: value(row, "TO_NAME"),
        theme_id: value(row, "Theme_ID"),
        theme: value(row, "Theme"),
        activity_id: ActionPlanRow.format_decimal_string(value(row, "Activity_ID")),
        activity: value(row, "Activity"),
        unit_type: value(row, "Unit_Type"),
        a_remark: value(row, "A_remark"),
        responsibel: value(row, "responsibel", "Responsible", "responsible"),
        asa_theme_id: value(row, "ASA_Theme_ID"),
        asa_theme: value(row, "ASA_Theme"),
        asa_activity_id: value(row, "ASA_Activity_ID"),
        asa_activity_name: value(row, "ASA_Activity_Name"),
        import_flag: 0,
        imported_at: imported_at,
        created_at: Time.current,
        updated_at: Time.current,
        **month_values,
        **target_values
      }
    end

    ActionPlanRow.active_import.update_all(import_flag: 1, updated_at: Time.current)
    ActionPlanRow.insert_all!(rows) if rows.any?
    rows.size
  end

  def import_vertical_mappings!
    rows = SpreadsheetRows.read(file_path(@vertical_mapping_file), sheet: :first).filter_map do |row|
      employee_code = ActionPlanVerticalMapping.normalize_code(value(row, "emp_id", "Employee ID", "Employee Code"))
      state_code = value(row, "State")
      asa_theme_id = ActionPlanRow.format_decimal_string(value(row, "ASA_Theme_ID", "ASA Theme ID"))
      next if employee_code.blank? || state_code.blank? || asa_theme_id.blank?

      employee = Employee.find_by(employee_code: employee_code)

      {
        employee_id: employee&.id,
        employee_code: employee_code,
        state_code: state_code.upcase,
        asa_theme_id: asa_theme_id,
        asa_theme: value(row, "ASA_Theme", "ASA Theme"),
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    unique_rows = rows.uniq { |row| [ row[:employee_code], row[:state_code], row[:asa_theme_id] ] }

    ActionPlanVerticalMapping.delete_all
    ActionPlanVerticalMapping.insert_all!(unique_rows) if unique_rows.any?
    unique_rows.size
  end

  def file_path(file)
    file.respond_to?(:path) ? file.path : file.to_s
  end

  def value(row, *headers)
    normalized = row.transform_keys { |key| key.to_s.squish.downcase }
    raw = headers.lazy.filter_map { |header| normalized[header.to_s.squish.downcase] }.first
    text = raw.to_s.gsub("&#160;", " ").squish
    text == "NULL" ? nil : text
  end

  def integer_value(row, *headers)
    Integer(value(row, *headers).presence || 0)
  rescue ArgumentError
    0
  end
end

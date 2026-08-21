class ActionPlanImporter
  MONTH_COLUMNS = %w[apr may jun jul aug sep oct nov dec jan feb mar].freeze
  TARGET_MONTH_COLUMNS = MONTH_COLUMNS.map { |month| "#{month}_t" }.freeze
  # The admin UI currently forces "append" so imports only insert new rows.
  # Keep replace/update modes available here for the future mode-wise workflow.
  ACTION_PLAN_IMPORT_MODES = %w[replace append update].freeze

  def initialize(project_file: nil, action_plan_file: nil, vertical_mapping_file: nil, action_plan_import_mode: "replace", uploaded_by: nil)
    @project_file = project_file
    @action_plan_file = action_plan_file
    @vertical_mapping_file = vertical_mapping_file
    @action_plan_import_mode = action_plan_import_mode.to_s.presence_in(ACTION_PLAN_IMPORT_MODES) || "replace"
    @uploaded_by = uploaded_by
  end

  def import!
    result = { project_ownerships: nil, action_plan_rows: nil, vertical_mappings: nil, vertical_logins: nil, preserved_changes: nil, reapplied_changes: nil }

    ActiveRecord::Base.transaction do
      result[:project_ownerships] = import_project_ownerships! if @project_file.present?
      if @action_plan_file.present?
        result[:action_plan_rows] = import_action_plan_rows!
        result[:preserved_changes] = @last_action_plan_change_result[:preserved_changes]
        result[:reapplied_changes] = @last_action_plan_change_result[:reapplied_changes]
      end

      if @vertical_mapping_file.present?
        result[:vertical_mappings] = import_vertical_mappings!
        result[:vertical_logins] = ActionPlanVerticalMapping.enable_employee_logins!
      end
    end

    result
  end

  private

  def import_project_ownerships!
    seen_po_ids = {}
    seen_projects = {}

    rows = SpreadsheetRows.read(file_path(@project_file)).filter_map do |row|
      po_id = value(row, "PO_ID").presence || value(row, "Project_ID", "Project ID")
      project_name = value(row, "Project")
      next if po_id.blank? || project_name.blank?

      # Full replace already clears the table; within the file, the first row for
      # a PO_ID / project wins so later duplicates cannot override it.
      project_key = ProjectOwnership.normalize_project_key(project_name)
      next if seen_po_ids[po_id] || seen_projects[project_key]

      seen_po_ids[po_id] = true
      seen_projects[project_key] = true

      po_name = value(row, "PO_Name")
      email_id = value(row, "Email_Id")
      project_owner_id = resolve_project_owner_id(
        value(row, "Project_owner_id"),
        po_name: po_name,
        email_id: email_id
      )

      {
        po_id: po_id,
        project_name: project_name,
        project_owner_id: project_owner_id,
        po_name: po_name,
        email_id: email_id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    ProjectOwnership.delete_all
    ProjectOwnership.insert_all!(rows) if rows.any?
    sync_pending_submission_approvers!
    rows.size
  end

  # Prefer the spreadsheet ID; if it is blank (common after manual edits), fall
  # back to email and then to the owner name so approvals still reach the right PO.
  def resolve_project_owner_id(raw_id, po_name:, email_id:)
    code = ProjectOwnership.normalize_employee_code(raw_id)
    return code if code.present? && Employee.exists?(employee_code: code)

    email = email_id.to_s.squish.downcase
    if email.present?
      by_email = Employee.where("LOWER(email) = ?", email).pick(:employee_code)
      return ProjectOwnership.normalize_employee_code(by_email) if by_email.present?
    end

    name = po_name.to_s.squish
    return if name.blank?

    by_name = Employee.where("LOWER(name) = ?", name.downcase).pick(:employee_code)
    return ProjectOwnership.normalize_employee_code(by_name) if by_name.present?

    # "K. K. Trivedi" should resolve to "Krishn Kumar Trivedi"
    initials_match = find_employee_code_by_initials(name)
    ProjectOwnership.normalize_employee_code(initials_match) if initials_match.present?
  end

  def find_employee_code_by_initials(po_name)
    parts = po_name.to_s.gsub(".", " ").split.map(&:presence).compact
    return if parts.size < 2

    last_name = parts.last.downcase
    initials = parts[0...-1].map { |part| part[0].downcase }

    Employee.find_each do |employee|
      name_parts = employee.name.to_s.split.map(&:presence).compact
      next if name_parts.size < 2
      next unless name_parts.last.downcase == last_name
      next unless name_parts[0...-1].map { |part| part[0].downcase } == initials

      return employee.employee_code
    end

    nil
  end

  # Pending submissions keep their stored po_approver_id; after a project-owner
  # reimport they must follow the new ownership so approvals land with the right PO.
  def sync_pending_submission_approvers!
    ActionPlanSubmission.where(status: "pending").find_each do |submission|
      ownership = ProjectOwnership.find_by(po_id: submission.po_id, project_name: submission.project_name) ||
        ProjectOwnership.find_by(po_id: submission.po_id) ||
        ProjectOwnership.find_by(project_name: submission.project_name)
      next unless ownership

      submission.update!(
        project_ownership: ownership,
        po_approver: ownership.owner_employee,
        coo_approver: ActionPlanSubmission.coo_employee,
        director_approver: ActionPlanSubmission.director_employee
      )
    end
  end

  def import_action_plan_rows!
    imported_at = Time.current
    rows = action_plan_rows_from_file(imported_at)

    raise_empty_action_plan_import! if rows.empty?

    preserved_changes = ActionPlanMonthChange.capture_active_deltas!(
      source: "before_import",
      status: "pending",
      changed_by: @uploaded_by
    )

    imported_count = case @action_plan_import_mode
    when "append"
      append_new_action_plan_rows!(rows)
    when "update"
      update_existing_action_plan_rows!(rows)
    else
      replace_action_plan_rows!(rows)
    end

    reapplied_changes = ActionPlanMonthChange.apply_active_overlays!
    @last_action_plan_change_result = {
      preserved_changes: preserved_changes,
      reapplied_changes: reapplied_changes
    }

    imported_count
  end

  def action_plan_rows_from_file(imported_at)
    SpreadsheetRows.read(file_path(@action_plan_file), sheet: :first).filter_map do |row|
      po_id = value(row, "PO_ID").presence || value(row, "Project_ID", "Project ID")
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
        user_id: value(row, "FCO ID", "FCO_ID", "FCOID", "User_Id", "User ID"),
        user_name: value(row, "FCO Name", "FCO_Name", "FCOName", "User_Name", "User Name"),
        to_id: value(row, "TO_ID"),
        to_name: value(row, "TO_NAME"),
        theme_id: value(row, "Project Theme ID", "Project_Theme_ID", "Theme_ID", "Theme ID"),
        theme: value(row, "Project Theme", "Project_Theme", "Theme"),
        activity_id: ActionPlanRow.format_decimal_string(value(row, "Project Activity ID", "Project_Activity_ID", "Activity_ID", "Activity ID")),
        activity: value(row, "Project Activity", "Project_Activity", "Activity"),
        unit_type: value(row, "Unit_Type"),
        a_remark: value(row, "A_remark"),
        responsibel: value(row, "responsibel", "Responsible", "responsible"),
        asa_theme_id: value(row, "ASA_Theme_ID"),
        asa_theme: value(row, "ASA_Theme"),
        asa_activity_id: value(row, "ASA_Activity_ID"),
        asa_activity_name: value(row, "ASA_Activity_Name"),
        planned_total: month_values.values.sum,
        import_flag: 0,
        imported_at: imported_at,
        created_at: Time.current,
        updated_at: Time.current,
        **month_values,
        **original_month_values(month_values),
        **target_values
      }
    end
  end

  def replace_action_plan_rows!(rows)
    ActionPlanRow.active_import.update_all(import_flag: 1, updated_at: Time.current)
    ActionPlanRow.insert_all!(rows)
    rows.size
  end

  def append_new_action_plan_rows!(rows)
    existing_keys = action_plan_rows_by_identity(ActionPlanRow.active_import).keys.index_with(true)
    new_rows = rows.reject { |row| existing_keys[action_plan_identity_key(row)] }
    ActionPlanRow.insert_all!(new_rows) if new_rows.any?
    new_rows.size
  end

  def update_existing_action_plan_rows!(rows)
    active_rows = action_plan_rows_by_identity(ActionPlanRow.active_import)
    updated_count = 0

    rows.each do |attributes|
      matches = active_rows[action_plan_identity_key(attributes)] || []
      next unless matches.size == 1

      row = matches.first
      row.assign_attributes(attributes.except(:id, :created_at, :import_flag))
      row.import_flag = 0
      row.save!
      updated_count += 1
    end

    updated_count
  end

  def raise_empty_action_plan_import!
    row = ActionPlanRow.new
    row.errors.add(
      :base,
      "No action plan rows found. Check that the file has PO_ID and Project columns with values."
    )
    raise ActiveRecord::RecordInvalid, row
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
    text = ActionPlanText.normalize(raw)
    text == "NULL" ? nil : text
  end

  def integer_value(row, *headers)
    Integer(value(row, *headers).presence || 0)
  rescue ArgumentError
    0
  end

  def original_month_values(month_values)
    month_values.transform_keys { |month| "original_#{month}" }
  end

  def action_plan_rows_by_identity(scope)
    scope.to_a.group_by { |row| action_plan_identity_key(row) }
  end

  def action_plan_identity_key(row)
    reader = row.is_a?(Hash) ? ->(attribute) { row[attribute] } : ->(attribute) { row.public_send(attribute) }

    [
      ActionPlanText.normalize(reader.call(:po_id)).to_s,
      ActionPlanText.normalize(reader.call(:project_name)).to_s,
      ActionPlanText.normalize(reader.call(:statte)).to_s,
      ActionPlanText.normalize(reader.call(:user_id)).to_s,
      ActionPlanText.normalize(reader.call(:to_id)).to_s,
      ActionPlanRow.format_decimal_string(ActionPlanText.normalize(reader.call(:asa_theme_id)).to_s),
      ActionPlanRow.format_decimal_string(ActionPlanText.normalize(reader.call(:asa_activity_id)).to_s)
    ]
  end
end

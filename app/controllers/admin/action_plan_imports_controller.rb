module Admin
  class ActionPlanImportsController < ApplicationController
    before_action :require_login
    before_action :require_admin
    DOWNLOAD_IMPORT_TYPES = %w[project_owner action_plan vertical_mapping].freeze
    ACTION_PLAN_ROW_FORM_ATTRIBUTES = [
      :id_new,
      :statte,
      :po_id,
      :project_name,
      :project_id,
      :project_owner,
      :user_id,
      :user_name,
      :to_id,
      :to_name,
      :theme_id,
      :theme,
      :activity_id,
      :activity,
      :unit_type,
      :a_remark,
      :responsibel,
      :asa_theme_id,
      :asa_theme,
      :asa_activity_id,
      :asa_activity_name,
      *ActionPlanRow::MONTH_COLUMNS.map(&:to_sym),
      *ActionPlanRow::TARGET_MONTH_COLUMNS.map(&:to_sym)
    ].freeze
    PROJECT_OWNERSHIP_FORM_ATTRIBUTES = %i[po_id project_name project_owner_id po_name email_id].freeze
    VERTICAL_MAPPING_FORM_ATTRIBUTES = %i[employee_id employee_code state_code asa_theme_id asa_theme].freeze
    before_action :set_action_plan_row, only: %i[update_action_plan_row toggle_action_plan_row]
    before_action :set_project_ownership, only: %i[update_project_ownership toggle_project_ownership]
    before_action :set_vertical_mapping, only: %i[update_vertical_mapping toggle_vertical_mapping]

    def index
      load_action_plan_import_context
    end

    def download
      filename = "action_plan_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx"
      send_data XlsxWorkbook.from_csv(ActionPlanExporter.active_csv, title: "Action Plan", sheet_name: "Action Plan"),
        filename: filename,
        type: XlsxWorkbook::CONTENT_TYPE
    end

    def create_action_plan_row
      row = ActionPlanRow.new(action_plan_row_params)
      prepare_action_plan_row!(row)
      row.active = true

      row.save!

      redirect_to admin_action_plan_imports_path(anchor: "action-plan-main-file"),
        notice: "Action plan row added."
    rescue ActiveRecord::RecordInvalid => error
      load_action_plan_import_context(form_row: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update_action_plan_row
      @action_plan_row.assign_attributes(action_plan_row_params)
      prepare_action_plan_row!(@action_plan_row)
      @action_plan_row.save!

      redirect_to admin_action_plan_imports_path(anchor: "action-plan-main-file"),
        notice: "Action plan row updated."
    rescue ActiveRecord::RecordInvalid => error
      load_action_plan_import_context(form_row: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_action_plan_row
      @action_plan_row.update!(active: !@action_plan_row.active?)

      redirect_to admin_action_plan_imports_path(anchor: "action-plan-main-file"),
        notice: "Action plan row #{@action_plan_row.active? ? "enabled" : "disabled"}."
    end

    def create_project_ownership
      ownership = ProjectOwnership.find_or_initialize_by(
        po_id: project_ownership_params[:po_id],
        project_name: project_ownership_params[:project_name]
      )
      ownership.assign_attributes(project_ownership_params)
      ownership.active = true
      ownership.save!
      ensure_project_owner_login!(ownership)

      redirect_to admin_action_plan_imports_path(anchor: "project-owners"),
        notice: "Project owner saved."
    rescue ActiveRecord::RecordInvalid => error
      load_action_plan_import_context(project_ownership_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update_project_ownership
      @project_ownership.assign_attributes(project_ownership_params)
      @project_ownership.save!
      ensure_project_owner_login!(@project_ownership)

      redirect_to admin_action_plan_imports_path(anchor: "project-owners"),
        notice: "Project owner updated."
    rescue ActiveRecord::RecordInvalid => error
      load_action_plan_import_context(project_ownership_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_project_ownership
      @project_ownership.update!(active: !@project_ownership.active?)
      ensure_project_owner_login!(@project_ownership) if @project_ownership.active?

      redirect_to admin_action_plan_imports_path(anchor: "project-owners"),
        notice: "Project owner #{@project_ownership.active? ? "enabled" : "disabled"}."
    end

    def create_vertical_mapping
      mapping = ActionPlanVerticalMapping.find_or_initialize_by(vertical_mapping_key_attributes)
      mapping.assign_attributes(vertical_mapping_params)
      prepare_vertical_mapping!(mapping)
      mapping.active = true
      mapping.save!
      User.ensure_login_for(mapping.employee) if mapping.employee&.active?

      redirect_to admin_action_plan_imports_path(anchor: "user-vertical-mapping"),
        notice: "User vertical mapping saved."
    rescue ActiveRecord::RecordInvalid => error
      load_action_plan_import_context(vertical_mapping_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update_vertical_mapping
      @vertical_mapping.assign_attributes(vertical_mapping_params)
      prepare_vertical_mapping!(@vertical_mapping)
      @vertical_mapping.save!
      User.ensure_login_for(@vertical_mapping.employee) if @vertical_mapping.active? && @vertical_mapping.employee&.active?

      redirect_to admin_action_plan_imports_path(anchor: "user-vertical-mapping"),
        notice: "User vertical mapping updated."
    rescue ActiveRecord::RecordInvalid => error
      load_action_plan_import_context(vertical_mapping_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_vertical_mapping
      @vertical_mapping.update!(active: !@vertical_mapping.active?)
      User.ensure_login_for(@vertical_mapping.employee) if @vertical_mapping.active? && @vertical_mapping.employee&.active?

      redirect_to admin_action_plan_imports_path(anchor: "user-vertical-mapping"),
        notice: "User vertical mapping #{@vertical_mapping.active? ? "enabled" : "disabled"}."
    end

    def download_latest_files
      files_by_type = latest_uploaded_files_by_type
      missing_types = DOWNLOAD_IMPORT_TYPES - files_by_type.keys
      if missing_types.present?
        missing_labels = missing_types.map { |import_type| ActionPlanImportFile::IMPORT_TYPES.fetch(import_type) }
        redirect_to admin_action_plan_imports_path, alert: "Upload/import missing files first: #{missing_labels.to_sentence}."
        return
      end

      files = DOWNLOAD_IMPORT_TYPES.map { |import_type| files_by_type.fetch(import_type) }
      missing_files = files.reject(&:file_available?)
      if missing_files.present?
        redirect_to admin_action_plan_imports_path, alert: "One or more uploaded files are missing from storage."
        return
      end

      filename = "action_plan_uploaded_files_#{Time.current.strftime("%Y%m%d_%H%M%S")}.zip"
      send_data zipped_import_files(files),
        filename: filename,
        type: "application/zip",
        disposition: "attachment"
    end

    def download_file
      import_file = ActionPlanImportFile.find(params[:id])

      unless import_file.file_available?
        redirect_to admin_action_plan_imports_path, alert: "Saved file is missing from storage."
        return
      end

      send_file import_file.absolute_path,
        filename: import_file.original_filename,
        type: import_file.content_type.presence || "application/octet-stream",
        disposition: "attachment"
    end

    def create
      if params[:project_file].blank? && params[:action_plan_file].blank? && params[:vertical_mapping_file].blank?
        redirect_to admin_action_plan_imports_path, alert: "Please choose at least one file to import."
        return
      end

      ActionPlanImportFile.capture_active_snapshot!(uploaded_by: current_user) if params[:action_plan_file].present?
      saved_files = capture_uploads!

      result = ActionPlanImporter.new(
        project_file: saved_files[:project_file]&.absolute_path,
        action_plan_file: saved_files[:action_plan_file]&.absolute_path,
        vertical_mapping_file: saved_files[:vertical_mapping_file]&.absolute_path,
        action_plan_import_mode: "append",
        uploaded_by: current_user
      ).import!

      mark_saved_files_imported!(saved_files, result)

      messages = []
      messages << "#{result[:project_ownerships]} project owners imported" if result[:project_ownerships]
      messages << "#{result[:action_plan_rows]} action plan rows imported" if result[:action_plan_rows]
      messages << "#{result[:vertical_mappings]} vertical mappings imported" if result[:vertical_mappings]
      messages << "#{result[:vertical_logins]} vertical users enabled for login" if result[:vertical_logins]
      if result[:action_plan_rows]
        id_count = ActionPlanRow.active_import.where.not(id_new: [ nil, "" ]).count
        messages << "#{id_count} rows with ID_New"
        messages << "#{result[:preserved_changes]} pending month changes preserved"
        if result[:reapplied_changes]
          messages << "#{result[:reapplied_changes][:applied_cells]} month changes reapplied"
          messages << "#{result[:reapplied_changes][:skipped_cells]} unmatched month changes" if result[:reapplied_changes][:skipped_cells].positive?
          messages << "#{result[:reapplied_changes][:merged_cells]} month changes already merged" if result[:reapplied_changes][:merged_cells].positive?
        end
      end

      redirect_to admin_action_plan_imports_path, notice: messages.join(", ").presence || "Action plan import completed."
    rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
      mark_saved_files_failed!(saved_files, error) if defined?(saved_files) && saved_files.present?
      redirect_to admin_action_plan_imports_path, alert: "Import failed: #{error.message}"
    end

    private

    def load_action_plan_import_context(form_row: nil, project_ownership_form: nil, vertical_mapping_form: nil)
      @project_ownerships = ProjectOwnership.order(active: :desc, po_id: :asc, project_name: :asc)
      @vertical_mappings = ActionPlanVerticalMapping.includes(:employee).order(active: :desc, employee_code: :asc, state_code: :asc, asa_theme_id: :asc)
      @action_plan_rows = ActionPlanRow.current_import.order(active: :desc, project_name: :asc, id: :asc)
      @import_files = ActionPlanImportFile.recent.limit(30)
      @employee_options = Employee.order(:name, :employee_code)
      @latest_action_plan_imported_at = ActionPlanRow.active_import.maximum(:imported_at)
      @summary = {
        project_ownerships: ProjectOwnership.active.count,
        disabled_project_ownerships: ProjectOwnership.disabled.count,
        action_plan_rows: ActionPlanRow.active_import.count,
        disabled_action_plan_rows: ActionPlanRow.disabled_import.count,
        vertical_mappings: ActionPlanVerticalMapping.active.count,
        disabled_vertical_mappings: ActionPlanVerticalMapping.disabled.count,
        archived_action_plan_rows: ActionPlanRow.where(import_flag: 1).count,
        projects: ActionPlanRow.active_import.distinct.count(:project_name),
        pending_submissions: ActionPlanSubmission.where(status: "pending").count
      }
      @action_plan_row_form = form_row ||
        ActionPlanRow.current_import.find_by(id: params[:edit_action_plan_row_id]) ||
        ActionPlanRow.new(import_flag: 0, active: true)
      @project_ownership_form = project_ownership_form ||
        ProjectOwnership.find_by(id: params[:edit_project_ownership_id]) ||
        ProjectOwnership.new(active: true)
      @vertical_mapping_form = vertical_mapping_form ||
        ActionPlanVerticalMapping.includes(:employee).find_by(id: params[:edit_vertical_mapping_id]) ||
        ActionPlanVerticalMapping.new(active: true)
    end

    def set_action_plan_row
      @action_plan_row = ActionPlanRow.current_import.find(params[:id])
    end

    def set_project_ownership
      @project_ownership = ProjectOwnership.find(params[:id])
    end

    def set_vertical_mapping
      @vertical_mapping = ActionPlanVerticalMapping.find(params[:id])
    end

    def action_plan_row_params
      params.require(:action_plan_row).permit(*ACTION_PLAN_ROW_FORM_ATTRIBUTES).tap do |attributes|
        attributes[:project_id] = attributes[:po_id] if attributes[:project_id].blank? && attributes[:po_id].present?
      end
    end

    def project_ownership_params
      params.require(:project_ownership).permit(*PROJECT_OWNERSHIP_FORM_ATTRIBUTES).tap do |attributes|
        attributes[:po_id] = attributes[:po_id].to_s.squish
        attributes[:project_name] = attributes[:project_name].to_s.squish
        attributes[:project_owner_id] = ProjectOwnership.normalize_employee_code(attributes[:project_owner_id])
        attributes[:po_name] = attributes[:po_name].to_s.squish
        attributes[:email_id] = attributes[:email_id].to_s.squish.downcase
      end
    end

    def vertical_mapping_params
      params.require(:action_plan_vertical_mapping).permit(*VERTICAL_MAPPING_FORM_ATTRIBUTES)
    end

    def vertical_mapping_key_attributes
      attributes = vertical_mapping_params
      employee_code = ActionPlanVerticalMapping.normalize_code(attributes[:employee_code])
      employee_code = Employee.find_by(id: attributes[:employee_id])&.employee_code if employee_code.blank? && attributes[:employee_id].present?
      {
        employee_code: employee_code,
        state_code: attributes[:state_code].to_s.squish.upcase,
        asa_theme_id: ActionPlanRow.format_decimal_string(attributes[:asa_theme_id])
      }
    end

    def prepare_vertical_mapping!(mapping)
      mapping.employee = Employee.find_by(id: mapping.employee_id) if mapping.employee_id.present?
      mapping.employee_code = mapping.employee.employee_code if mapping.employee && mapping.employee_code.blank?
    end

    def ensure_project_owner_login!(ownership)
      employee = ownership.owner_employee
      return unless ownership.active? && employee&.active?

      User.ensure_login_for(employee)
    end

    def prepare_action_plan_row!(row)
      row.import_flag = 0
      row.imported_at ||= Time.current

      ActionPlanRow::MONTH_COLUMNS.each do |month|
        value = row.public_send(month).to_i
        row.public_send("#{month}=", value)
        row.public_send("original_#{month}=", value)
      end

      ActionPlanRow::TARGET_MONTH_COLUMNS.each do |month|
        row.public_send("#{month}=", row.public_send(month).to_i)
      end

      row.planned_total = ActionPlanRow::MONTH_COLUMNS.sum { |month| row.public_send(month).to_i }
    end

    def capture_uploads!
      {
        project_file: capture_upload(:project_file, "project_owner"),
        action_plan_file: capture_upload(:action_plan_file, "action_plan"),
        vertical_mapping_file: capture_upload(:vertical_mapping_file, "vertical_mapping")
      }.compact
    end

    def capture_upload(param_name, import_type)
      upload = params[param_name]
      return if upload.blank?

      ActionPlanImportFile.capture!(upload: upload, import_type: import_type, uploaded_by: current_user)
    end

    def mark_saved_files_imported!(saved_files, result)
      saved_files[:project_file]&.mark_imported!(result[:project_ownerships])
      saved_files[:action_plan_file]&.mark_imported!(result[:action_plan_rows])
      saved_files[:vertical_mapping_file]&.mark_imported!(result[:vertical_mappings])
    end

    def mark_saved_files_failed!(saved_files, error)
      saved_files.each_value { |file| file.mark_failed!(error.message) }
    end

    def latest_uploaded_files_by_type
      DOWNLOAD_IMPORT_TYPES.to_h do |import_type|
        [
          import_type,
          ActionPlanImportFile.where(import_type: import_type, status: "imported").recent.first
        ]
      end.compact
    end

    def zipped_import_files(files)
      Zip::OutputStream.write_buffer do |zip|
        files.each do |import_file|
          zip.put_next_entry(zip_entry_name(import_file))
          File.open(import_file.absolute_path, "rb") do |file|
            IO.copy_stream(file, zip)
          end
        end
      end.string
    end

    def zip_entry_name(import_file)
      folder = import_file.import_type.to_s
      filename = File.basename(import_file.original_filename.to_s)
      File.join(folder, filename.presence || "uploaded_file")
    end
  end
end

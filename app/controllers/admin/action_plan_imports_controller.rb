module Admin
  class ActionPlanImportsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def index
      @project_ownerships = ProjectOwnership.order(:po_id, :project_name)
      @vertical_mappings = ActionPlanVerticalMapping.includes(:employee).order(:employee_code, :state_code, :asa_theme_id)
      @import_files = ActionPlanImportFile.recent.limit(30)
      @latest_action_plan_imported_at = ActionPlanRow.active_import.maximum(:imported_at)
      @summary = {
        project_ownerships: ProjectOwnership.count,
        action_plan_rows: ActionPlanRow.active_import.count,
        vertical_mappings: ActionPlanVerticalMapping.count,
        archived_action_plan_rows: ActionPlanRow.where(import_flag: 1).count,
        projects: ActionPlanRow.active_import.distinct.count(:project_name),
        pending_submissions: ActionPlanSubmission.where(status: "pending").count
      }
    end

    def download
      filename = "action_plan_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv"
      send_data ActionPlanExporter.active_csv,
        filename: filename,
        type: "text/csv; charset=utf-8"
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
        vertical_mapping_file: saved_files[:vertical_mapping_file]&.absolute_path
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
      end

      redirect_to admin_action_plan_imports_path, notice: messages.join(", ").presence || "Action plan import completed."
    rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
      mark_saved_files_failed!(saved_files, error) if defined?(saved_files) && saved_files.present?
      redirect_to admin_action_plan_imports_path, alert: "Import failed: #{error.message}"
    end

    private

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
  end
end

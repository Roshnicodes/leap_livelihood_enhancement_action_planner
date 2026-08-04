module Admin
  class ActionPlanImportsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def index
      @project_ownerships = ProjectOwnership.order(:po_id, :project_name)
      @vertical_mappings = ActionPlanVerticalMapping.includes(:employee).order(:employee_code, :state_code, :asa_theme_id)
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

    def create
      if params[:project_file].blank? && params[:action_plan_file].blank? && params[:vertical_mapping_file].blank?
        redirect_to admin_action_plan_imports_path, alert: "Please choose at least one file to import."
        return
      end

      result = ActionPlanImporter.new(
        project_file: params[:project_file],
        action_plan_file: params[:action_plan_file],
        vertical_mapping_file: params[:vertical_mapping_file]
      ).import!

      messages = []
      messages << "#{result[:project_ownerships]} project owners imported" if result[:project_ownerships]
      messages << "#{result[:action_plan_rows]} action plan rows imported" if result[:action_plan_rows]
      messages << "#{result[:vertical_mappings]} vertical mappings imported" if result[:vertical_mappings]
      if result[:action_plan_rows]
        id_count = ActionPlanRow.active_import.where.not(id_new: [nil, ""]).count
        messages << "#{id_count} rows with ID_New"
      end

      redirect_to admin_action_plan_imports_path, notice: messages.join(", ").presence || "Action plan import completed."
    rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
      redirect_to admin_action_plan_imports_path, alert: "Import failed: #{error.message}"
    end
  end
end

module Admin
  class PbImportsController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def index
      @import_files = PbImportFile.recent.limit(30)
      @latest_imported_at = @import_files.imported.first&.imported_at
      @summary = {
        activities: BliActivity.count,
        projects: BliActivity.distinct.count(:project_name),
        verticals: BliActivity.distinct.count(:vertical_name),
        allocated: BliActivity.sum(:allocated_fund),
        import_files: @import_files.size
      }
    end

    def download
      import_file = PbImportFile.ensure_latest_source!

      if import_file&.file_available?
        PbSourceFileUpdater.update_latest!(ProjectSummarySubmission.approved_items_for_pb_download)
        import_file.reload
        send_file import_file.absolute_path,
          filename: import_file.original_filename,
          type: import_file.content_type.presence || PbActivityExporter::XLSX_CONTENT_TYPE,
          disposition: "attachment"
      else
        filename = "pb_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx"
        send_data PbActivityExporter.active_xlsx,
          filename: filename,
          type: PbActivityExporter::XLSX_CONTENT_TYPE
      end
    end

    def download_file
      import_file = PbImportFile.find(params[:id])

      unless import_file.file_available?
        redirect_to admin_pb_imports_path, alert: "Saved file is missing from storage."
        return
      end

      send_file import_file.absolute_path,
        filename: import_file.original_filename,
        type: import_file.content_type.presence || "application/octet-stream",
        disposition: "attachment"
    end

    def create
      if params[:pb_file].blank? && params[:parent_activity_file].blank?
        redirect_to admin_pb_imports_path, alert: "Please choose a P&B source file or parent activity mapping file to import."
        return
      end

      backup_active_pb_if_needed
      saved_mapping_file = capture_parent_activity_mapping
      saved_source_file = capture_pb_source
      sync_source_file = saved_source_file || PbImportFile.latest_source
      clear_summaries = false

      mapping_count = import_parent_activity_mapping(saved_mapping_file)
      source_row_count = import_pb_source(sync_source_file, clear_summaries: clear_summaries) if sync_source_file && (saved_source_file || saved_mapping_file)

      saved_source_file&.mark_imported!(source_row_count)

      redirect_to admin_pb_imports_path, notice: import_message(mapping_count: mapping_count, source_row_count: source_row_count, clear_summaries: clear_summaries)
    rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
      saved_mapping_file&.mark_failed!(error.message)
      saved_source_file&.mark_failed!(error.message)
      redirect_to admin_pb_imports_path, alert: "P&B import failed: #{error.message}"
    end

    private

    def capture_parent_activity_mapping
      return if params[:parent_activity_file].blank?

      PbImportFile.capture!(upload: params[:parent_activity_file], uploaded_by: current_user, file_kind: "parent_activity_mapping")
    end

    def capture_pb_source
      return if params[:pb_file].blank?

      PbImportFile.capture!(upload: params[:pb_file], uploaded_by: current_user)
    end

    def backup_active_pb_if_needed
      return unless params[:pb_file].present? || (params[:parent_activity_file].present? && PbImportFile.latest_source.present?)

      PbImportFile.capture_active_snapshot!(uploaded_by: current_user)
    end

    def import_parent_activity_mapping(saved_mapping_file)
      return unless saved_mapping_file

      imported = ParentActivityAssignmentImporter.new(file_path: saved_mapping_file.absolute_path.to_s).import!
      saved_mapping_file.mark_imported!(imported)
      imported
    end

    def import_pb_source(sync_source_file, clear_summaries:)
      BliActivitySync.new(source_path: sync_source_file.absolute_path.to_s, save_history: false).call(clear_summaries: clear_summaries)
    end

    def import_message(mapping_count:, source_row_count:, clear_summaries:)
      messages = []
      messages << "#{mapping_count} parent activity mappings imported" if mapping_count
      messages << "#{source_row_count} P&B activities synced" if source_row_count
      messages << "old P&B summary submissions cleared" if clear_summaries
      messages << "previous active P&B file saved in history" if params[:pb_file].present?
      messages.join(", ").presence || "P&B import completed."
    end
  end
end

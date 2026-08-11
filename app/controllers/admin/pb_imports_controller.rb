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

  end
end

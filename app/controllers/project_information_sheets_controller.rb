require "csv"

class ProjectInformationSheetsController < ApplicationController
  before_action :require_login
  before_action :require_admin, only: :create

  def index
    load_workspace

    respond_to do |format|
      format.html
      format.csv do
        send_data export_csv,
          filename: "project_information_sheet_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(export_csv, title: "Project Information Sheet", sheet_name: "Project Info"),
          filename: "project_information_sheet_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  def create
    if params[:project_information_file].blank?
      redirect_to project_information_sheets_path, alert: "Please choose a CSV or XLSX file."
      return
    end

    result = ProjectInformationSheetImporter.new(
      file: params[:project_information_file],
      uploaded_by: current_user
    ).import!

    redirect_to project_information_sheets_path,
      notice: "Project information imported. Created: #{result.created}, Updated: #{result.updated}, Skipped: #{result.skipped}."
  rescue ArgumentError => e
    redirect_to project_information_sheets_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_information_sheets_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def load_workspace
    @financial_year_options = ProjectInformationSheet.financial_year_options
    @project_options = ProjectInformationSheet.reorder(:project_title, :project_id).map(&:project_option_label).uniq
    @selected_project = params[:project].presence_in(@project_options)
    @selected_financial_year = params[:financial_year].presence_in(@financial_year_options)
    @sheets = ProjectInformationSheet.by_project_id
      .for_project(@selected_project)
      .with_financial_year(@selected_financial_year)
    @year_columns = ReportFinancialYear.options.reverse
  end

  def export_csv
    CSV.generate(headers: true) do |csv|
      csv << ProjectInformationSheet::HEADER_LABELS

      @sheets.each do |sheet|
        csv << [
          sheet.project_id,
          sheet.project_title,
          sheet.donor,
          sheet.category,
          sheet.project_period,
          *@year_columns.map { |year| sheet.amount_for(year).to_s },
          sheet.total.to_s("F"),
          sheet.project_location,
          sheet.project_area_map,
          sheet.donor_reporting_officer,
          sheet.start_date,
          sheet.end_date,
          sheet.project_objectives,
          sheet.households_to_be_covered,
          sheet.fco_name,
          sheet.po,
          sheet.reporting_system,
          sheet.physical,
          sheet.financial,
          sheet.annexure
        ]
      end
    end
  end
end

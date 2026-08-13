class DonorReportUploadsController < ApplicationController
  before_action :require_login
  before_action :require_upload_access, only: %i[create create_report_type]

  def index
    load_workspace
  end

  def records
    load_workspace
  end

  def create
    upload = DonorReportUpload.new(upload_params)
    upload.uploaded_by = current_user

    if upload.save
      redirect_to donor_report_records_path, notice: "Donor report uploaded."
    else
      redirect_to donor_report_uploads_path, alert: upload.errors.full_messages.to_sentence
    end
  end

  def create_report_type
    report_type = DonorReportType.new(name: params.dig(:donor_report_type, :name).to_s.squish)

    if report_type.save
      redirect_to donor_report_uploads_path, notice: "Reports name added."
    else
      redirect_to donor_report_uploads_path, alert: report_type.errors.full_messages.to_sentence
    end
  end

  private

  def upload_params
    params.require(:donor_report_upload).permit(:project_name, :donor_report_type_id, :frequency, :financial_year, :submission_date, :document_file, :screenshot_file)
  end

  def load_workspace
    @can_upload_donor_report = current_user&.admin?
    @project_options = project_options
    @report_types = DonorReportType.active.ordered
    @frequency_options = DonorReportUpload::FREQUENCIES
    @financial_year_options = financial_year_options
    @selected_project = params[:project].presence_in(@project_options)
    @selected_frequency = params[:frequency].presence_in(@frequency_options)
    @selected_financial_year = params[:financial_year].presence_in(@financial_year_options)
    @selected_report_type_id = params[:report_type_id].to_s.presence
    @uploads = DonorReportUpload.recent
      .for_project(@selected_project)
      .for_financial_year(@selected_financial_year)
      .for_frequency(@selected_frequency)
      .for_report_type(@selected_report_type_id)
  end

  def project_options
    (
      BliActivity.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name) +
      ProjectOwnership.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name)
    ).compact_blank.uniq.sort
  end

  def financial_year_options
    saved = DonorReportUpload.distinct.pluck(:financial_year)

    (ReportFinancialYear.options + saved).compact_blank.uniq.sort.reverse
  end

  def require_upload_access
    return if current_user&.admin?

    redirect_to donor_report_uploads_path, alert: "PMC access required to upload donor reports."
  end
end

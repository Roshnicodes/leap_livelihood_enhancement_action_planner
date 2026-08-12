class FundReportUploadsController < ApplicationController
  before_action :require_login
  before_action :require_upload_access, only: %i[create create_report_type]

  def index
    load_workspace
  end

  def records
    load_workspace
  end

  def create
    upload = FundReportUpload.new(upload_params)
    upload.uploaded_by = current_user

    if upload.save
      redirect_to fund_report_records_path, notice: "Fund report uploaded."
    else
      redirect_to fund_report_uploads_path, alert: upload.errors.full_messages.to_sentence
    end
  end

  def create_report_type
    report_type = FundReportType.new(name: params.dig(:fund_report_type, :name).to_s.squish)

    if report_type.save
      redirect_to fund_report_uploads_path, notice: "Reports name added."
    else
      redirect_to fund_report_uploads_path, alert: report_type.errors.full_messages.to_sentence
    end
  end

  private

  def upload_params
    params.require(:fund_report_upload).permit(
      :project_name,
      :fund_report_type_id,
      :financial_year,
      :submission_letter_date,
      :submission_letter_amount,
      :submission_receipt_date,
      :submission_receipt_amount,
      :document_file,
      :screenshot_file
    )
  end

  def load_workspace
    @can_upload_fund_report = current_user&.admin?
    @project_options = project_options
    @report_types = FundReportType.active.ordered
    @financial_year_options = financial_year_options
    @selected_project = params[:project].presence_in(@project_options)
    @selected_financial_year = params[:financial_year].presence_in(@financial_year_options)
    @selected_report_type_id = params[:report_type_id].to_s.presence
    @uploads = FundReportUpload.recent
      .for_project(@selected_project)
      .for_financial_year(@selected_financial_year)
      .for_report_type(@selected_report_type_id)
  end

  def project_options
    (
      BliActivity.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name) +
      ProjectOwnership.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name)
    ).compact_blank.uniq.sort
  end

  def financial_year_options
    current = FundReportUpload.financial_year_for
    saved = FundReportUpload.distinct.pluck(:financial_year)
    future_start = current.split("-").first.to_i + 1
    future = "#{future_start}-#{future_start + 1}"
    (saved + [ current, future ]).compact_blank.uniq.sort.reverse
  end

  def require_upload_access
    return if current_user&.admin?

    redirect_to fund_report_uploads_path, alert: "PMC access required to upload fund reports."
  end
end

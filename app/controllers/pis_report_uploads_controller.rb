class PisReportUploadsController < ApplicationController
  before_action :require_login
  before_action :require_upload_access, only: %i[create create_document_type]

  def index
    load_workspace
  end

  def create
    document = PisReportDocument.new(document_params)
    document.uploaded_by = current_user

    if document.save
      redirect_to pis_report_uploads_path, notice: "PIS report document uploaded."
    else
      redirect_to pis_report_uploads_path, alert: document.errors.full_messages.to_sentence
    end
  end

  def create_document_type
    document_type = PisDocumentType.new(name: params.dig(:pis_document_type, :name).to_s.squish)

    if document_type.save
      redirect_to pis_report_uploads_path, notice: "Doc name added."
    else
      redirect_to pis_report_uploads_path, alert: document_type.errors.full_messages.to_sentence
    end
  end

  private

  def document_params
    params.require(:pis_report_document).permit(:project_name, :pis_document_type_id, :financial_year, :submission_date, :file)
  end

  def load_workspace
    @can_upload_pis_report = current_user&.admin?
    @project_options = project_options
    @document_types = PisDocumentType.active.ordered
    @financial_year_options = financial_year_options
    @selected_project = params[:project].presence_in(@project_options)
    @selected_financial_year = params[:financial_year].presence_in(@financial_year_options)
    @selected_document_type_id = params[:document_type_id].to_s.presence
    @documents = PisReportDocument.recent
      .for_project(@selected_project)
      .for_financial_year(@selected_financial_year)
      .for_document_type(@selected_document_type_id)
  end

  def project_options
    (
      BliActivity.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name) +
      ProjectOwnership.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name)
    ).compact_blank.uniq.sort
  end

  def financial_year_options
    current = PisReportDocument.financial_year_for
    saved = PisReportDocument.distinct.pluck(:financial_year)
    future_start = current.split("-").first.to_i + 1
    future = "#{future_start}-#{future_start + 1}"
    (saved + [ current, future ]).compact_blank.uniq.sort.reverse
  end

  def require_upload_access
    return if current_user&.admin?

    redirect_to pis_report_uploads_path, alert: "PMC access required to upload documents."
  end
end

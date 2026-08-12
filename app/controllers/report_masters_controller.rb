class ReportMastersController < ApplicationController
  before_action :require_login
  before_action :require_admin

  def index
    load_masters
  end

  def create_pis_document_type
    document_type = PisDocumentType.new(name: params.dig(:pis_document_type, :name).to_s.squish)

    if document_type.save
      redirect_to report_masters_path, notice: "PIS doc name added."
    else
      redirect_to report_masters_path, alert: document_type.errors.full_messages.to_sentence
    end
  end

  def create_donor_report_type
    report_type = DonorReportType.new(name: params.dig(:donor_report_type, :name).to_s.squish)

    if report_type.save
      redirect_to report_masters_path, notice: "Donor report name added."
    else
      redirect_to report_masters_path, alert: report_type.errors.full_messages.to_sentence
    end
  end

  def create_fund_report_type
    report_type = FundReportType.new(name: params.dig(:fund_report_type, :name).to_s.squish)

    if report_type.save
      redirect_to report_masters_path, notice: "Fund report name added."
    else
      redirect_to report_masters_path, alert: report_type.errors.full_messages.to_sentence
    end
  end

  private

  def load_masters
    @pis_document_types = PisDocumentType.ordered
    @donor_report_types = DonorReportType.ordered
    @fund_report_types = FundReportType.ordered
  end
end

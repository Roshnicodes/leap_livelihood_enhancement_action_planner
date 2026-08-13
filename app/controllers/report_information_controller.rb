class ReportInformationController < ApplicationController
  before_action :require_login

  def index
    @project_options = project_options
    @financial_year_options = financial_year_options
    @selected_project = params[:project].presence_in(@project_options)
    @selected_financial_year = params[:financial_year].presence_in(@financial_year_options)
    @has_filters = @selected_project.present? && @selected_financial_year.present?

    @pis_documents = @has_filters ? pis_documents : PisReportDocument.none
    @donor_reports = @has_filters ? donor_reports : DonorReportUpload.none
    @fund_reports = @has_filters ? fund_reports : FundReportUpload.none
    @project_information_sheets = @has_filters ? project_information_sheets : ProjectInformationSheet.none
    @report_sections = build_report_sections
    @total_records = @report_sections.sum { |section| section[:records].size } + @project_information_sheets.size
  end

  private

  def project_options
    (
      BliActivity.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name) +
      ProjectOwnership.where.not(project_name: [ nil, "" ]).distinct.pluck(:project_name) +
      PisReportDocument.distinct.pluck(:project_name) +
      DonorReportUpload.distinct.pluck(:project_name) +
      FundReportUpload.distinct.pluck(:project_name) +
      ProjectInformationSheet.reorder(:project_title, :project_id).map(&:project_option_label)
    ).compact_blank.uniq.sort
  end

  def financial_year_options
    (
      ReportFinancialYear.options +
      PisReportDocument.distinct.pluck(:financial_year) +
      DonorReportUpload.distinct.pluck(:financial_year) +
      FundReportUpload.distinct.pluck(:financial_year) +
      ProjectInformationSheet.financial_year_options
    ).compact_blank.uniq.sort.reverse
  end

  def pis_documents
    PisReportDocument.recent
      .for_project(@selected_project)
      .for_financial_year(@selected_financial_year)
  end

  def donor_reports
    DonorReportUpload.recent
      .for_project(@selected_project)
      .for_financial_year(@selected_financial_year)
  end

  def fund_reports
    FundReportUpload.recent
      .for_project(@selected_project)
      .for_financial_year(@selected_financial_year)
  end

  def project_information_sheets
    ProjectInformationSheet.recent
      .for_project(@selected_project)
      .with_financial_year(@selected_financial_year)
  end

  def build_report_sections
    [
      *pis_sections,
      *donor_sections,
      *fund_sections
    ].sort_by { |section| [ section[:sort_group], section[:title].to_s.downcase ] }
  end

  def pis_sections
    @pis_documents.group_by(&:pis_document_type).map do |document_type, documents|
      {
        sort_group: 1,
        title: document_type&.name || "PIS Document",
        category: "PIS",
        records: documents.map { |document| pis_record(document) }
      }
    end
  end

  def donor_sections
    @donor_reports.group_by(&:donor_report_type).map do |report_type, reports|
      {
        sort_group: 2,
        title: report_type&.name || "Donor Report",
        category: "Donor",
        records: reports.map { |report| donor_record(report) }
      }
    end
  end

  def fund_sections
    @fund_reports.group_by(&:fund_report_type).map do |report_type, reports|
      {
        sort_group: 3,
        title: report_type&.name || "Fund Report",
        category: "Fund",
        records: reports.map { |report| fund_record(report) }
      }
    end
  end

  def pis_record(document)
    {
      project: document.project_name,
      name: document.pis_document_type&.name,
      date_label: "Submission Date",
      date: document.submission_date,
      fy: document.financial_year,
      amount_label: nil,
      amount: nil,
      document_label: "Document Upload",
      document_attachment: document.file,
      screenshot_attachment: document.screenshot_file,
      uploaded_by: uploaded_by_label(document),
      uploaded_at: document.created_at
    }
  end

  def donor_record(report)
    {
      project: report.project_name,
      name: report.donor_report_type&.name,
      date_label: "Submission Date",
      date: report.submission_date,
      fy: report.financial_year,
      amount_label: "Frequency",
      amount: report.frequency,
      document_label: "Document Upload",
      document_attachment: report.document_file.attached? ? report.document_file : report.file,
      screenshot_attachment: report.screenshot_file,
      uploaded_by: uploaded_by_label(report),
      uploaded_at: report.created_at
    }
  end

  def fund_record(report)
    {
      project: report.project_name,
      name: report.fund_report_type&.name,
      date_label: "Receipt Date",
      date: report.submission_receipt_date,
      fy: report.financial_year,
      amount_label: "Receipt Amount",
      amount: helpers.currency(report.submission_receipt_amount),
      document_label: "Document Upload",
      document_attachment: report.document_file,
      screenshot_attachment: report.screenshot_file,
      uploaded_by: uploaded_by_label(report),
      uploaded_at: report.created_at
    }
  end

  def uploaded_by_label(record)
    record.uploaded_by&.admin? ? "PMC" : record.uploaded_by&.employee&.name || "-"
  end
end

class AddFinancialYearToDonorReportUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :donor_report_uploads, :financial_year, :string, null: false, default: "2026-2027"
    add_index :donor_report_uploads, [ :project_name, :financial_year, :donor_report_type_id, :frequency, :created_at ],
      name: "idx_donor_uploads_project_year_type_frequency_recent",
      if_not_exists: true
  end
end

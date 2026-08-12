class AddFinancialYearToFundReportUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :fund_report_uploads, :financial_year, :string, null: false, default: "2026-2027"
    add_index :fund_report_uploads, [ :project_name, :financial_year, :fund_report_type_id, :created_at ],
      name: "idx_fund_uploads_project_year_type_recent",
      if_not_exists: true
  end
end

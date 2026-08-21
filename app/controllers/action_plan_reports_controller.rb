class ActionPlanReportsController < ApplicationController
  before_action :require_login
  before_action :require_admin

  def index
    @report = ActionPlanStatusReport.new
    @fco_submission_rows = @report.fco_submission_rows
    @fco_approval_rows = @report.fco_approval_rows
    @vertical_summary_rows = @report.vertical_summary_rows
    @action_plan_detail_rows = @report.action_plan_detail_rows
    @achievement_detail_rows = @report.achievement_detail_rows

    respond_to do |format|
      format.html
      format.csv do
        send_data @report.csv,
          filename: "action_plan_status_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data @report.xlsx,
          filename: "action_plan_status_report_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end
end

require "csv"

class AchievementEntryRecordsController < ApplicationController
  include ActionPlanPresenter

  before_action :require_login
  before_action :require_achievement_record_access

  MONTH_OPTIONS = ActionPlanRow::MONTH_COLUMNS.map { |month| [ month.capitalize, month ] }.freeze
  STATUS_OPTIONS = [
    [ "All Status", "" ],
    [ "Saved Draft", "draft" ],
    [ "Pending Approval", "pending" ],
    [ "Approved", "approved" ],
    [ "Returned", "returned" ]
  ].freeze

  def index
    load_records

    respond_to do |format|
      format.html
      format.csv do
        send_data achievement_entry_records_csv,
          filename: "achievement_entry_records_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(achievement_entry_records_csv, title: "Achievement Entry Records", sheet_name: "Records"),
          filename: "achievement_entry_records_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  private

  def require_achievement_record_access
    return if current_user&.admin?
    return if current_user&.employee&.action_plan_fco?

    redirect_to dashboard_path, alert: "Achievement entry record access required."
  end

  def load_records
    scope = accessible_action_plan_rows

    @project_options = distinct_options(scope, :project_name, :project_name)
    @selected_project = selected_filter(params[:project], @project_options.map(&:last))
    scope = scope.where(project_name: @selected_project) if @selected_project.present?

    @state_options = distinct_options(scope, :statte, :statte)
    @selected_state = selected_filter(params[:state], @state_options.map(&:last))
    scope = scope.where(statte: @selected_state) if @selected_state.present?

    @vertical_options = distinct_options(scope, :asa_theme, :asa_theme)
    @selected_vertical = selected_filter(params[:vertical], @vertical_options.map(&:last))
    scope = scope.where(asa_theme: @selected_vertical) if @selected_vertical.present?

    @fco_options = fco_options_for(scope)
    @selected_fco_id = selected_filter(params[:fco_id], @fco_options.map(&:last))
    scope = scope.where(user_id: fco_filter_ids(@selected_fco_id)) if @selected_fco_id.present?

    @to_options = distinct_options(scope, :to_name, :to_id)
    @selected_to_id = selected_filter(params[:to_id], @to_options.map(&:last))
    scope = scope.where(to_id: @selected_to_id) if @selected_to_id.present?

    @period_options = action_plan_period_options
    @selected_period = selected_period
    @month_options = MONTH_OPTIONS
    @selected_period_month = selected_period_month
    months = period_months(@selected_period, @selected_period_month)

    @status_options = STATUS_OPTIONS
    @selected_status = selected_filter(params[:status], STATUS_OPTIONS.map(&:last))

    @records = build_entry_records(scope, months)
    @records.select! { |record| record[:status_key] == @selected_status } if @selected_status.present?
  end

  def accessible_action_plan_rows
    rows = ActionPlanRow.active_import
    return rows if current_user.admin?

    fco_ids = ActionPlanFcoMapping.ensure_for_employee(current_user.employee).pluck(:fco_id)
    rows.where(user_id: fco_ids)
  end

  def distinct_options(scope, label_attribute, value_attribute)
    scope
      .where.not(value_attribute => [ nil, "" ])
      .distinct
      .reorder(label_attribute, value_attribute)
      .pluck(label_attribute, value_attribute)
      .map { |label, value| [ label.presence || value.to_s, value.to_s ] }
  end

  def fco_options_for(scope)
    options = distinct_options(scope, :user_name, :user_id)
    ActionPlanFcoGroup.group_options(options)
  end

  def fco_filter_ids(fco_id)
    fco_id.to_s.split(",").flat_map { |id| ActionPlanFcoGroup.ids_for(id) }.compact_blank.uniq
  end

  def selected_filter(value, allowed_values)
    return if value.blank?

    allowed_values.find { |allowed| allowed.to_s == value.to_s }
  end

  def build_entry_records(scope, months)
    rows = scope
      .order(:project_name, :user_name, :to_name, :asa_theme_id, :asa_activity_id, :id)
      .to_a
    return [] if rows.blank?

    row_ids = rows.map(&:id)
    details_by_key = AchievementEntryDetail
      .where(action_plan_row_id: row_ids, month: months)
      .includes(files_attachments: :blob)
      .index_by { |detail| [ detail.action_plan_row_id, detail.month ] }

    submission_rows_by_key = AchievementSubmissionRow
      .joins(:achievement_submission)
      .where(action_plan_row_id: row_ids, month: months)
      .includes(achievement_submission: :employee)
      .order(Arel.sql("achievement_submissions.submitted_at DESC"))
      .each_with_object({}) do |submission_row, lookup|
        lookup[[ submission_row.action_plan_row_id, submission_row.month ]] ||= submission_row
      end

    rows.flat_map do |row|
      months.filter_map do |month|
        achievement_value = row.public_send("#{month}_t").to_i
        detail = details_by_key[[ row.id, month ]]
        submission_row = submission_rows_by_key[[ row.id, month ]]
        next if achievement_value.zero? && detail.blank? && submission_row.blank?

        submission = submission_row&.achievement_submission
        {
          row: row,
          month: month,
          target_value: submission_row&.target_value || row.public_send(month).to_i,
          achievement_value: submission_row&.achievement_value || achievement_value,
          detail: detail,
          submission: submission,
          status_key: achievement_record_status_key(submission),
          status_label: achievement_record_status_label(submission)
        }
      end
    end
  end

  def achievement_record_status_key(submission)
    return "draft" if submission.blank?
    return submission.status if submission.returned? || submission.approved?

    "pending"
  end

  def achievement_record_status_label(submission)
    return "Saved Draft" if submission.blank?

    submission.status_label
  end

  def achievement_entry_records_csv
    CSV.generate(headers: true) do |csv|
      csv << [
        "Project", "State", "FCO ID", "FCO", "TO ID", "TO", "Vertical", "ASA Theme ID",
        "ASA Activity ID", "ASA Activity", "Month", "Target", "Achievement", "Status",
        "Submitted By", "Submitted At", "Remark", "Files"
      ]

      @records.each do |record|
        row = record[:row]
        detail = record[:detail]
        submission = record[:submission]

        csv << [
          row.project_name,
          row.statte,
          row.user_id,
          ActionPlanFcoGroup.name_for(row.user_id, row.user_name),
          row.to_id,
          row.to_name,
          row.asa_theme,
          ActionPlanRow.format_decimal_string(row.asa_theme_id),
          ActionPlanRow.format_decimal_string(row.asa_activity_id),
          row.asa_activity_name.presence || row.activity,
          record[:month].capitalize,
          record[:target_value],
          record[:achievement_value],
          record[:status_label],
          submission&.employee&.name,
          submission&.submitted_at&.in_time_zone("Asia/Kolkata")&.strftime("%d %b %Y, %I:%M %p"),
          detail&.remark,
          detail&.files&.attachments&.map { |file| file.filename.to_s }&.join(", ")
        ]
      end
    end
  end
end

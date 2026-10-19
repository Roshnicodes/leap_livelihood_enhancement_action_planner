# Every file uploaded with an achievement entry, grouped by month. Same access
# as Achievement Entry Record (MIS sees all, an FCO only its own rows), but
# rows from earlier action plan imports are kept, so files uploaded before a
# re-import still show.
class AchievementDocumentsController < AchievementEntryRecordsController
  MONTH_FILTER_OPTIONS = [ [ "All Months", "" ], *MONTH_OPTIONS ].freeze

  def index
    scope = rows_with_documents

    @project_options = distinct_options(scope, :project_name, :project_name)
    @selected_project = selected_filter(params[:project], @project_options.map(&:last))
    scope = scope.where(project_name: @selected_project) if @selected_project.present?

    @fco_options = fco_options_for(scope)
    @selected_fco_id = selected_filter(params[:fco_id], @fco_options.map(&:last))
    scope = scope.where(user_id: fco_filter_ids(@selected_fco_id)) if @selected_fco_id.present?

    @to_options = distinct_options(scope, :to_name, :to_id)
    @selected_to_id = selected_filter(params[:to_id], @to_options.map(&:last))
    scope = scope.where(to_id: @selected_to_id) if @selected_to_id.present?

    @month_options = MONTH_FILTER_OPTIONS
    @selected_month = selected_filter(params[:month], ActionPlanRow::MONTH_COLUMNS)

    details = details_with_files.where(action_plan_row_id: scope.select(:id))
    details = details.where(month: @selected_month) if @selected_month.present?
    details = details.includes(:action_plan_row, files_attachments: :blob).to_a

    @documents_by_month = details
      .group_by(&:month)
      .sort_by { |month, _| ActionPlanRow::MONTH_COLUMNS.index(month).to_i }
      .map do |month, month_details|
        [ month, month_details.sort_by { |detail| document_sort_key(detail.action_plan_row) } ]
      end
    @document_count = details.sum { |detail| detail.files.attachments.size }
    @activity_count = details.size
  end

  private

  def details_with_files
    AchievementEntryDetail.where(
      id: ActiveStorage::Attachment.where(record_type: "AchievementEntryDetail", name: "files").select(:record_id)
    )
  end

  def rows_with_documents
    rows = ActionPlanRow.where(id: details_with_files.select(:action_plan_row_id))
    return rows if current_user.admin?

    fco_ids = ActionPlanFcoMapping
      .ensure_for_employee(current_user.employee)
      .pluck(:fco_id)
      .flat_map { |fco_id| ActionPlanFcoGroup.ids_for(fco_id) }
      .uniq
    rows.where(user_id: fco_ids)
  end

  def document_sort_key(row)
    [
      row.project_name.to_s,
      ActionPlanFcoGroup.name_for(row.user_id, row.user_name),
      row.to_name.to_s,
      ActionPlanRow.format_decimal_string(row.asa_theme_id).to_f,
      ActionPlanRow.format_decimal_string(row.asa_activity_id).to_f,
      row.id
    ]
  end
end

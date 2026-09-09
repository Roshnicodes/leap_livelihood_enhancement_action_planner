require "csv"
require "rexml/document"
require "tempfile"
require "zip"

class AchievementEntriesController < ApplicationController
  before_action :require_login
  before_action :set_entry_context

  ACHIEVEMENT_ROW_ID_HEADER = "Row ID".freeze
  ACHIEVEMENT_REMARK_HEADER = "Remark".freeze
  ACHIEVEMENT_UPLOAD_EXTENSIONS = %w[.csv .xlsx].freeze
  MONTH_OPTIONS = ActionPlanRow::MONTH_COLUMNS.map { |month| [ month.capitalize, month ] }.freeze

  def show
    # Opening Achievement Entry from menu (no filters) must start blank.
    # Ignore leftover query params unless user explicitly chose filters.
    if params[:to_id].blank? && params[:project].blank? && params[:month].blank? && (!current_user.admin? || params[:fco_id].blank?)
      # Ensure clean URL without empty query junk like ?project=&month=
      if request.query_string.present?
        redirect_to achievement_entry_path and return
      end
    end

    load_selection

    respond_to do |format|
      format.html
      format.csv do
        send_data achievement_entry_csv,
          filename: "achievement_entry_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
          type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data XlsxWorkbook.from_csv(achievement_entry_csv, title: "Achievement Entry", sheet_name: "Achievement Entry"),
          filename: "achievement_entry_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
          type: XlsxWorkbook::CONTENT_TYPE
      end
    end
  end

  def update
    load_selection

    if current_user.admin? && @selected_fco_id.blank?
      redirect_to achievement_entry_path, alert: "Please choose FCO before editing achievements."
      return
    end

    if @selected_to_id.blank? || @selected_project.blank? || @selected_month.blank?
      redirect_to achievement_entry_path, alert: "Please choose TO, project and month."
      return
    end

    if !current_user.admin? && all_selected_rows_locked?
      redirect_to selected_achievement_entry_path,
        alert: "Vertical approval is done for one or more rows. Achievement changes are locked."
      return
    end

    unless ActionPlanRow::MONTH_COLUMNS.include?(@selected_month)
      redirect_to achievement_entry_path, alert: "Please choose a valid month."
      return
    end

    changed_row_ids = changed_entry_row_ids_from_params
    save_achievement_values!
    save_entry_details!
    reload_selected_rows!
    refresh_unreviewed_pending_submission_rows!(changed_row_ids)
    requeued_count = current_user.admin? ? requeue_reviewed_achievements_for_mis_edit!(changed_row_ids) : 0
    load_selection

    if params[:commit].to_s == "Submit for Approval"
      created_count = create_achievement_submissions!(raise_when_blank: requeued_count.zero?)
      total_count = created_count + requeued_count
      redirect_to selected_achievement_entry_path,
        notice: "#{total_count} achievement approval request#{'s' unless total_count == 1} submitted."
      return
    end

    notice = if requeued_count.positive?
      "#{requeued_count} achievement approval request#{'s' unless requeued_count == 1} sent again after MIS edit."
    else
      "Achievement rows, remarks and files saved for #{@selected_month.capitalize}."
    end
    redirect_to selected_achievement_entry_path, notice: notice
  rescue ActiveRecord::RecordInvalid => error
    action = params[:commit].to_s == "Submit for Approval" ? "Submit" : "Save"
    redirect_to selected_achievement_entry_path, alert: "#{action} failed: #{error.record.errors.full_messages.to_sentence}"
  end

  def import_excel
    load_selection

    unless current_user.admin?
      redirect_to achievement_entry_path, alert: "MIS access required to upload edited achievement Excel."
      return
    end

    if @selected_fco_id.blank?
      redirect_to achievement_entry_path, alert: "Please choose FCO before uploading edited Excel."
      return
    end

    if @selected_to_id.blank? || @selected_project.blank? || @selected_month.blank?
      redirect_to achievement_entry_path(fco_id: @selected_fco_id), alert: "Please choose TO, project and month before uploading edited Excel."
      return
    end

    unless ActionPlanRow::MONTH_COLUMNS.include?(@selected_month)
      redirect_to achievement_entry_path(fco_id: @selected_fco_id), alert: "Please choose a valid month."
      return
    end

    if @rows.blank?
      redirect_to selected_achievement_entry_path, alert: "No activities found for this FCO, TO, project and month."
      return
    end

    if params[:achievement_excel_file].blank?
      redirect_to selected_achievement_entry_path, alert: "Please choose the edited achievement Excel file."
      return
    end

    changes = achievement_excel_changes_from(achievement_excel_rows_from_upload(params[:achievement_excel_file]))

    if changes.blank?
      redirect_to selected_achievement_entry_path,
        alert: "No valid Row ID changes found. Download the latest Excel format from this page and upload it after editing."
      return
    end

    changed_row_ids = apply_excel_achievement_changes!(changes)

    if changed_row_ids.blank?
      redirect_to selected_achievement_entry_path, alert: "Excel uploaded, but no achievement changes were found."
      return
    end

    reload_selected_rows!
    refresh_unreviewed_pending_submission_rows!(changed_row_ids)
    requeued_count = requeue_reviewed_achievements_for_mis_edit!(changed_row_ids)
    load_selection

    notice = "#{changed_row_ids.size} achievement row#{'s' unless changed_row_ids.size == 1} updated from Excel."
    if requeued_count.positive?
      notice = "#{notice} #{requeued_count} approval request#{'s' unless requeued_count == 1} sent again after MIS edit."
    end

    redirect_to selected_achievement_entry_path, notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to selected_achievement_entry_path, alert: "Excel upload failed: #{error.record.errors.full_messages.to_sentence}"
  rescue CSV::MalformedCSVError, Zip::Error, REXML::ParseException, ArgumentError => error
    redirect_to selected_achievement_entry_path, alert: "Excel upload failed: #{error.message}"
  end

  def submit
    load_selection

    if current_user.admin? && @selected_fco_id.blank?
      redirect_to achievement_entry_path, alert: "Please choose FCO before submitting achievements."
      return
    end

    if @rows.blank?
      redirect_to achievement_entry_path, alert: "Choose TO, project and month before submitting."
      return
    end

    if !current_user.admin? && all_selected_rows_locked?
      redirect_to selected_achievement_entry_path,
        alert: "These achievements are already locked after vertical approval."
      return
    end

    changed_row_ids = changed_entry_row_ids_from_params
    save_achievement_values!
    save_entry_details!
    reload_selected_rows!
    refresh_unreviewed_pending_submission_rows!(changed_row_ids)
    requeued_count = current_user.admin? ? requeue_reviewed_achievements_for_mis_edit!(changed_row_ids) : 0
    load_selection
    created_count = create_achievement_submissions!(raise_when_blank: requeued_count.zero?)
    total_count = created_count + requeued_count

    redirect_to selected_achievement_entry_path,
      notice: "#{total_count} achievement approval request#{'s' unless total_count == 1} submitted."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to selected_achievement_entry_path, alert: "Submit failed: #{error.record.errors.full_messages.to_sentence}"
  end

  private

  def set_entry_context
    if current_user.admin?
      @employee = nil
      @fco_mappings = ActionPlanFcoMapping.none
      @fco_display_mappings = []
      return
    end

    @employee = current_user.employee
    @fco_mappings = ActionPlanFcoMapping.ensure_for_employee(@employee).order(:fco_name)
    @fco_display_mappings = fco_display_mappings

    return if @fco_mappings.exists?

    redirect_to dashboard_path, alert: "No action plan FCO mapping found for this login."
  end

  def fco_display_mappings
    mappings = @fco_mappings.to_a
    ActionPlanFcoGroup
      .group_options(mappings.map { |mapping| [ mapping.fco_name, mapping.fco_id ] })
      .map { |name, ids| { fco_name: name, fco_id: ids } }
  end

  def load_selection
    @month_options = MONTH_OPTIONS
    @admin_entry = current_user.admin?

    if @admin_entry
      all_rows = ActionPlanRow.active_import
      @project_options = project_filter_options_for(all_rows)
      @selected_project = selected_value(params[:project], @project_options)
      project_rows = @selected_project.present? ? all_rows.where(project_name: @selected_project) : all_rows

      @fco_options = fco_filter_options_for(project_rows)
      @selected_fco_id = selected_value(params[:fco_id], @fco_options.map(&:last))
      @fco_ids = @selected_fco_id.present? ? fco_filter_ids(@selected_fco_id) : []
      @scoped_rows = @selected_fco_id.present? ? project_rows.where(user_id: @fco_ids) : ActionPlanRow.none
      @fco_display_mappings = selected_fco_display_mappings
      to_option_rows = @selected_fco_id.present? ? @scoped_rows : project_rows
    else
      @fco_options = []
      @selected_fco_id = nil
      @fco_ids = @fco_mappings.pluck(:fco_id).flat_map { |fco_id| ActionPlanFcoGroup.ids_for(fco_id) }.uniq
      @scoped_rows = ActionPlanRow.active_import.where(user_id: @fco_ids)
      @project_options = []
      to_option_rows = @scoped_rows
    end

    @to_options = to_option_rows
      .where.not(to_id: [ nil, "" ])
      .distinct
      .order(:to_name, :to_id)
      .pluck(:to_name, :to_id)
      .map { |to_name, to_id| [ to_name.presence || "TO #{to_id}", to_id.to_s ] }

    @selected_to_id = selected_value(params[:to_id], @to_options.map(&:last))
    to_rows = if @selected_to_id.present? && (!@admin_entry || @selected_fco_id.present?)
      @scoped_rows.where(to_id: @selected_to_id)
    else
      @scoped_rows.none
    end

    unless @admin_entry
      @project_options = @selected_to_id.present? ? project_filter_options_for(to_rows) : []
      @selected_project = selected_value(params[:project], @project_options)
    end

    @selected_month = selected_value(params[:month], ActionPlanRow::MONTH_COLUMNS)

    @rows = if @selected_to_id.present? && @selected_project.present? && @selected_month.present? && (!@admin_entry || @selected_fco_id.present?)
      to_rows.where(project_name: @selected_project)
        .order(:asa_theme_id, :asa_activity_id, :activity_id, :id)
        .to_a
    else
      []
    end

    @entry_details_by_row_id = if @rows.present? && @selected_month.present?
      AchievementEntryDetail.for_rows(@rows.map(&:id), @selected_month)
    else
      {}
    end

    target_rows = @selected_month.present? ? @rows.select { |row| row.public_send(@selected_month).to_i.positive? } : []
    @target_rows_count = target_rows.size
    row_ids = @rows.map(&:id)
    actual_locked_row_ids = @rows.present? && @selected_month.present? ? locked_submission_row_ids_for(row_ids, @selected_month) : []
    @locked_submission_row_ids = current_user.admin? ? [] : actual_locked_row_ids
    @active_submission_row_ids = @rows.present? && @selected_month.present? ? active_submission_row_ids_for(row_ids, @selected_month) : []
    @editable_row_count = row_ids.size - @locked_submission_row_ids.size
    @submission_candidate_row_count = if current_user.admin?
      admin_submission_candidate_row_count(row_ids, @selected_month)
    else
      (row_ids - @active_submission_row_ids).size
    end
    @locked_submission_count = @rows.present? && @selected_month.present? ? AchievementSubmission.locked_for_rows(row_ids, @selected_month).count : 0
    @active_submission_count = if @rows.present? && @selected_month.present?
      AchievementSubmission.active_for_rows(row_ids, @selected_month).count
    else
      0
    end
    @selected_returned_submissions = if @rows.present? && @selected_month.present?
      unresolved_returned_submissions(
        AchievementSubmission
          .returned_for_rows(row_ids, @selected_month)
          .includes(:vertical_approver, :po_approver, :coo_approver, :director_approver, achievement_submission_rows: :action_plan_row)
          .order(submitted_at: :desc, id: :desc)
      )
    else
      []
    end
    @open_returned_submissions = unresolved_returned_submissions(
      AchievementSubmission
        .where(status: "returned", fco_id: @fco_ids)
        .includes(:vertical_approver, :po_approver, :coo_approver, :director_approver, achievement_submission_rows: :action_plan_row)
        .order(submitted_at: :desc, id: :desc)
    )
    @returned_entry_contexts = returned_entry_contexts_for(@open_returned_submissions)
  end

  # Never auto-pick the first dropdown option — user must choose explicitly.
  def selected_value(value, options)
    return if value.blank?

    options.find { |option| option.to_s == value.to_s }
  end

  def clean_achievement_value(value)
    Integer(value.presence || 0, exception: false).to_i.clamp(0, 2_147_483_647)
  end

  def fco_filter_options_for(rows)
    options = rows
      .where.not(user_id: [ nil, "" ])
      .distinct
      .reorder(:user_name, :user_id)
      .pluck(:user_name, :user_id)
      .map { |label, value| [ label.presence || value.to_s, value.to_s ] }

    ActionPlanFcoGroup.group_options(options)
  end

  def project_filter_options_for(rows)
    rows
      .where.not(project_name: [ nil, "" ])
      .distinct
      .reorder(:project_name)
      .pluck(:project_name)
  end

  def fco_filter_ids(fco_id)
    fco_id.to_s.split(",").flat_map { |id| ActionPlanFcoGroup.ids_for(id) }.compact_blank.uniq
  end

  def selected_fco_display_mappings
    return [] if @selected_fco_id.blank?

    [
      {
        fco_name: @fco_options.assoc(@selected_fco_id)&.first || ActionPlanFcoGroup.name_for(@selected_fco_id),
        fco_id: @selected_fco_id
      }
    ]
  end

  def selected_achievement_entry_path
    path_params = {
      to_id: @selected_to_id,
      project: @selected_project,
      month: @selected_month
    }.compact_blank
    path_params[:fco_id] = @selected_fco_id if current_user.admin? && @selected_fco_id.present?

    achievement_entry_path(path_params)
  end

  def changed_entry_row_ids_from_params
    return [] if @rows.blank? || @selected_month.blank?

    changed_ids = []
    selected_row_ids = @rows.map(&:id)
    achievement_column = "#{@selected_month}_t"
    permitted_values = params[:achievements].respond_to?(:to_unsafe_h) ? params[:achievements].to_unsafe_h : {}
    value_ids = editable_row_ids_for(permitted_values.keys) & selected_row_ids
    current_values = @scoped_rows.where(id: value_ids).pluck(:id, achievement_column).to_h

    value_ids.each do |row_id|
      changed_ids << row_id if current_values[row_id].to_i != clean_achievement_value(permitted_values[row_id.to_s])
    end

    remarks = params[:remarks].respond_to?(:to_unsafe_h) ? params[:remarks].to_unsafe_h : {}
    detail_ids = editable_row_ids_for(remarks.keys) & selected_row_ids
    existing_details = AchievementEntryDetail
      .where(action_plan_row_id: detail_ids, month: @selected_month)
      .includes(files_attachments: :blob)
      .index_by(&:action_plan_row_id)

    detail_ids.each do |row_id|
      existing_remark = existing_details[row_id]&.remark.to_s.strip
      changed_ids << row_id if existing_remark != remarks[row_id.to_s].to_s.strip
    end

    uploads = params[:files].respond_to?(:to_unsafe_h) ? params[:files].to_unsafe_h : {}
    upload_ids = editable_row_ids_for(uploads.keys) & selected_row_ids
    upload_ids.each do |row_id|
      changed_ids << row_id if Array(uploads[row_id.to_s]).compact_blank.present?
    end

    purge_ids = Array(params[:purge_file_ids]).map(&:to_s).reject(&:blank?)
    if purge_ids.present? && existing_details.present?
      details_by_id = existing_details.values.index_by(&:id)
      ActiveStorage::Attachment
        .where(id: purge_ids, record_type: "AchievementEntryDetail", record_id: details_by_id.keys)
        .pluck(:record_id)
        .each do |detail_id|
          row_id = details_by_id[detail_id]&.action_plan_row_id
          changed_ids << row_id if row_id.present?
        end
    end

    changed_ids.uniq
  end

  def save_achievement_values!
    achievement_column = "#{@selected_month}_t"
    permitted_values = params[:achievements].respond_to?(:to_unsafe_h) ? params[:achievements].to_unsafe_h : {}
    editable_ids = editable_row_ids_for(permitted_values.keys)
    accessible_rows = @scoped_rows.where(id: editable_ids)

    ActionPlanRow.transaction do
      accessible_rows.find_each do |row|
        row.update!(achievement_column => clean_achievement_value(permitted_values[row.id.to_s]))
      end
    end
  end

  def save_entry_details!
    remarks = params[:remarks].respond_to?(:to_unsafe_h) ? params[:remarks].to_unsafe_h : {}
    uploads = params[:files].respond_to?(:to_unsafe_h) ? params[:files].to_unsafe_h : {}
    purge_ids = Array(params[:purge_file_ids]).map(&:to_s).reject(&:blank?)
    accessible_ids = @scoped_rows.where(id: editable_row_ids_for(@rows.map(&:id))).pluck(:id)
    existing = AchievementEntryDetail
      .where(action_plan_row_id: accessible_ids, month: @selected_month)
      .includes(files_attachments: :blob)
      .index_by(&:action_plan_row_id)

    AchievementEntryDetail.transaction do
      accessible_ids.each do |row_id|
        remark = remarks[row_id.to_s].to_s.strip
        new_files = Array(uploads[row_id.to_s]).compact_blank
        detail = existing[row_id]

        if detail.nil?
          next if remark.blank? && new_files.blank?

          detail = AchievementEntryDetail.new(action_plan_row_id: row_id, month: @selected_month)
        end

        detail.remark = remark
        detail.files.attach(new_files) if new_files.present?

        if purge_ids.present? && detail.persisted? && detail.files.attached?
          detail.files.attachments.select { |attachment| purge_ids.include?(attachment.id.to_s) }.each(&:purge)
        end

        detail.save!
      end
    end
  end

  def achievement_excel_rows_from_upload(upload)
    extension = File.extname(upload.original_filename.to_s).presence || File.extname(upload.path.to_s)
    extension = extension.to_s.downcase

    unless ACHIEVEMENT_UPLOAD_EXTENSIONS.include?(extension)
      raise ArgumentError, "Upload only .xlsx or .csv files."
    end

    Tempfile.create([ "achievement-entry-upload", extension ]) do |file|
      file.binmode
      upload.rewind if upload.respond_to?(:rewind)
      file.write(upload.read)
      file.flush

      SpreadsheetRows.read(file.path, sheet: :first, header_match: [ ACHIEVEMENT_ROW_ID_HEADER ])
    end
  end

  def achievement_excel_changes_from(spreadsheet_rows)
    selected_rows_by_id = @rows.index_by(&:id)

    spreadsheet_rows.each_with_object({}) do |spreadsheet_row, changes|
      row_id = Integer(spreadsheet_value(spreadsheet_row, ACHIEVEMENT_ROW_ID_HEADER).to_s.strip, exception: false)
      next unless row_id.present? && selected_rows_by_id.key?(row_id)

      change = {}
      achievement_value = spreadsheet_value(
        spreadsheet_row,
        achievement_excel_achievement_header,
        "Achievement",
        "Achievement Value"
      )
      remark_value = spreadsheet_value(spreadsheet_row, ACHIEVEMENT_REMARK_HEADER)

      change[:achievement_value] = clean_achievement_value(achievement_value) if achievement_value.to_s.strip.present?
      change[:remark] = remark_value.to_s.strip if remark_value.to_s.strip.present?

      changes[row_id] = change if change.present?
    end
  end

  def apply_excel_achievement_changes!(changes)
    achievement_column = "#{@selected_month}_t"
    row_ids = changes.keys
    selected_rows_by_id = @rows.index_by(&:id)
    existing_details = AchievementEntryDetail
      .where(action_plan_row_id: row_ids, month: @selected_month)
      .index_by(&:action_plan_row_id)
    changed_row_ids = []

    ActiveRecord::Base.transaction do
      row_ids.each do |row_id|
        row = selected_rows_by_id[row_id]
        change = changes[row_id]
        next if row.blank? || change.blank?

        if change.key?(:achievement_value) && row.public_send(achievement_column).to_i != change[:achievement_value].to_i
          row.update!(achievement_column => change[:achievement_value].to_i)
          changed_row_ids << row.id
        end

        next unless change.key?(:remark)

        detail = existing_details[row.id] ||
          AchievementEntryDetail.new(action_plan_row_id: row.id, month: @selected_month)
        if detail.remark.to_s.strip != change[:remark].to_s.strip
          detail.remark = change[:remark]
          detail.save!
          existing_details[row.id] = detail
          changed_row_ids << row.id
        end
      end
    end

    changed_row_ids.uniq
  end

  def achievement_excel_achievement_header
    "#{@selected_month.to_s.capitalize} Achievement"
  end

  def spreadsheet_value(row, *headers)
    lookup = row.to_h.each_with_object({}) do |(key, value), values_by_header|
      values_by_header[key.to_s.squish.downcase] ||= value
    end

    headers.each do |header|
      value = lookup[header.to_s.squish.downcase]
      return value unless value.nil?
    end

    nil
  end

  def reload_selected_rows!
    @rows.each(&:reload)
  end

  def create_achievement_submissions!(rows: @rows, skip_active_filter: false, raise_when_blank: true)
    candidate_rows = Array(rows)
    row_ids = candidate_rows.map(&:id)
    active_row_ids = skip_active_filter ? [] : active_submission_row_ids_for(row_ids, @selected_month)
    submission_rows = candidate_rows.reject { |row| active_row_ids.include?(row.id) }

    if submission_rows.blank?
      return 0 unless raise_when_blank

      raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
        submission.errors.add(:base, "Approval request already exists for this selected month/project.")
      end)
    end

    # Rows without ASA Theme ID cannot be routed to a vertical approver.
    # Keep them out of the approval package (achievements can still be saved as draft).
    submittable_rows = submission_rows.select { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id).present? }
    if submittable_rows.blank?
      raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
        submission.errors.add(:base, "No activities with ASA Theme ID found for approval. Check the action plan import.")
      end)
    end

    # One review per TO + vertical owner (all of that vertical's themes together).
    # Example: June / Palsud / Anurag = single request with themes 1,2,3,11,12 inside.
    state_codes = submittable_rows.map { |row| row.statte.to_s.squish.upcase }.uniq
    theme_ids = submittable_rows.map { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id) }.uniq
    mappings_by_key = ActionPlanVerticalMapping.active
      .where(state_code: state_codes, asa_theme_id: theme_ids)
      .includes(:employee)
      .index_by { |mapping| [ mapping.state_code, mapping.asa_theme_id ] }

    mapping_by_row = {}
    approver_by_row = {}
    submittable_rows.each do |row|
      state_code = row.statte.to_s.squish.upcase
      asa_theme_id = ActionPlanRow.format_decimal_string(row.asa_theme_id)
      mapping = mappings_by_key[[ state_code, asa_theme_id ]]
      mapping_by_row[row.id] = mapping
      approver_by_row[row.id] = resolve_vertical_approver(mapping)
    end

    missing_route_labels = submittable_rows.filter_map do |row|
      next if approver_by_row[row.id].present?

      state_code = row.statte.to_s.squish.upcase.presence || "?"
      theme_id = ActionPlanRow.format_decimal_string(row.asa_theme_id)
      "#{state_code} / ASA Theme #{theme_id}"
    end.uniq

    if missing_route_labels.present?
      raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
        submission.errors.add(
          :base,
          "Vertical approver is not mapped for #{missing_route_labels.join('; ')}. Update User Vertical Mapping and retry."
        )
      end)
    end

    ownerships_by_po_project = ProjectOwnership.active
      .where(po_id: submittable_rows.map(&:po_id).uniq, project_name: submittable_rows.map(&:project_name).uniq)
      .index_by { |ownership| [ ownership.po_id, ownership.project_name ] }
    ownerships_by_po = ProjectOwnership.active.where(po_id: submittable_rows.map(&:po_id).uniq).index_by(&:po_id)
    ownerships_by_project = ProjectOwnership.active.where(project_name: submittable_rows.map(&:project_name).uniq).index_by(&:project_name)

    groups = submittable_rows.group_by do |row|
      [
        row.project_name.to_s,
        row.to_id.to_s,
        row.statte.to_s.squish.upcase,
        approver_by_row[row.id]&.id
      ]
    end
    created_count = 0

    AchievementSubmission.transaction do
      groups.each do |(project_name, _to_id, state_code, _vertical_employee_id), rows|
        sample = rows.first
        vertical_approver = approver_by_row[sample.id]
        submission_employee = submission_employee_for(sample)
        theme_ids = rows.map { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id) }.uniq.sort_by { |id| id.to_f }
        ownership = ownerships_by_po_project[[ sample.po_id, sample.project_name ]] ||
          ownerships_by_po[sample.po_id] ||
          ownerships_by_project[sample.project_name]

        if submission_employee.blank?
          raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
            submission.errors.add(:base, "FCO employee mapping is not available for #{sample.user_name.presence || sample.user_id}.")
          end)
        end

        submission = AchievementSubmission.create!(
          employee: submission_employee,
          fco_id: sample.user_id,
          fco_name: ActionPlanFcoGroup.name_for(sample.user_id, sample.user_name),
          to_id: sample.to_id,
          to_name: sample.to_name,
          project_name: project_name,
          po_id: sample.po_id,
          state_code: state_code,
          asa_theme_id: theme_ids.join(","),
          month: @selected_month,
          submission_remark: params[:submission_remark].to_s.strip,
          vertical_approver: vertical_approver,
          po_approver: ownership&.owner_employee,
          coo_approver: AchievementSubmission.coo_employee,
          director_approver: AchievementSubmission.director_employee,
          submitted_at: Time.current
        )

        rows.each do |row|
          submission.achievement_submission_rows.create!(
            action_plan_row: row,
            month: @selected_month,
            target_value: row.public_send(@selected_month).to_i,
            achievement_value: row.public_send("#{@selected_month}_t").to_i
          )
        end

        created_count += 1
      end
    end

    created_count
  end

  def resolve_vertical_approver(mapping)
    return if mapping.blank?

    mapping.employee || Employee.find_by(employee_code: mapping.employee_code)
  end

  def submission_employee_for(row)
    return @employee unless current_user.admin?

    latest_submission_for_row(row.id, @selected_month)&.employee ||
      ActionPlanFcoMapping.active
        .where(fco_id: fco_mapping_lookup_ids(row.user_id))
        .includes(:employee)
        .first&.employee
  end

  def latest_submission_for_row(row_id, month)
    AchievementSubmission
      .joins(:achievement_submission_rows)
      .where(achievement_submission_rows: { action_plan_row_id: row_id, month: month })
      .includes(:employee)
      .order(submitted_at: :desc, id: :desc)
      .first
  end

  def fco_mapping_lookup_ids(fco_id)
    [
      ActionPlanFcoGroup.canonical_id(fco_id),
      *ActionPlanFcoGroup.ids_for(fco_id)
    ].uniq
  end

  def all_selected_rows_locked?
    row_ids = @rows.map(&:id)
    locked_row_ids = locked_submission_row_ids_for(row_ids, @selected_month)

    row_ids.present? && (row_ids - locked_row_ids).blank?
  end

  def editable_row_ids_for(row_ids)
    ids = row_ids.map(&:to_i).uniq
    return ids if current_user.admin?

    ids - locked_submission_row_ids_for(ids, @selected_month)
  end

  def admin_submission_candidate_row_count(row_ids, month)
    ids = row_ids.map(&:to_i).uniq
    return 0 if ids.blank? || month.blank?

    unsubmitted_ids = ids - active_submission_row_ids_for(ids, month)
    requeueable_ids = reviewed_active_submission_row_ids_for(ids, month) - unreviewed_pending_submission_row_ids_for(ids, month)
    (unsubmitted_ids | requeueable_ids).size
  end

  def active_submission_row_ids_for(row_ids, month)
    ids = row_ids.map(&:to_i).uniq
    return [] if ids.blank? || month.blank?

    AchievementSubmissionRow
      .joins(:achievement_submission)
      .where(action_plan_row_id: ids, month: month)
      .where(achievement_submissions: { status: %w[pending approved] })
      .distinct
      .pluck(:action_plan_row_id)
  end

  def locked_submission_row_ids_for(row_ids, month)
    ids = row_ids.map(&:to_i).uniq
    return [] if ids.blank? || month.blank?

    AchievementSubmissionRow
      .joins(:achievement_submission)
      .where(action_plan_row_id: ids, month: month)
      .where(achievement_submissions: { status: %w[pending approved] })
      .where.not(achievement_submissions: { vertical_reviewed_at: nil })
      .distinct
      .pluck(:action_plan_row_id)
  end

  def unreviewed_pending_submission_row_ids_for(row_ids, month)
    ids = row_ids.map(&:to_i).uniq
    return [] if ids.blank? || month.blank?

    AchievementSubmissionRow
      .joins(:achievement_submission)
      .where(action_plan_row_id: ids, month: month)
      .where(achievement_submissions: { status: "pending", current_stage: "vertical", vertical_reviewed_at: nil })
      .distinct
      .pluck(:action_plan_row_id)
  end

  def reviewed_active_submission_row_ids_for(row_ids, month)
    ids = row_ids.map(&:to_i).uniq
    return [] if ids.blank? || month.blank?

    AchievementSubmissionRow
      .joins(:achievement_submission)
      .where(action_plan_row_id: ids, month: month)
      .where(achievement_submissions: { status: %w[pending approved] })
      .where("achievement_submissions.vertical_reviewed_at IS NOT NULL OR achievement_submissions.status = ?", "approved")
      .distinct
      .pluck(:action_plan_row_id)
  end

  def refresh_unreviewed_pending_submission_rows!(row_ids)
    ids = row_ids.map(&:to_i).uniq
    return if ids.blank? || @selected_month.blank?

    AchievementSubmissionRow
      .joins(:achievement_submission)
      .where(action_plan_row_id: ids, month: @selected_month)
      .where(achievement_submissions: { status: "pending", current_stage: "vertical", vertical_reviewed_at: nil })
      .includes(:action_plan_row)
      .find_each do |submission_row|
        row = submission_row.action_plan_row
        submission_row.update!(
          target_value: row.public_send(@selected_month).to_i,
          achievement_value: row.public_send("#{@selected_month}_t").to_i
        )
      end
  end

  def requeue_reviewed_achievements_for_mis_edit!(row_ids)
    ids = row_ids.map(&:to_i).uniq
    return 0 if ids.blank? || @selected_month.blank?

    reviewed_ids = reviewed_active_submission_row_ids_for(ids, @selected_month)
    return 0 if reviewed_ids.blank?

    already_pending_ids = unreviewed_pending_submission_row_ids_for(reviewed_ids, @selected_month)
    requeue_ids = reviewed_ids - already_pending_ids
    return 0 if requeue_ids.blank?

    AchievementSubmission.transaction do
      detach_reviewed_pending_rows_for_mis_edit!(requeue_ids)
      rows = @rows.select { |row| requeue_ids.include?(row.id) }
      create_achievement_submissions!(rows: rows, skip_active_filter: true, raise_when_blank: false)
    end
  end

  def detach_reviewed_pending_rows_for_mis_edit!(row_ids)
    submissions = AchievementSubmission
      .joins(:achievement_submission_rows)
      .where(status: "pending")
      .where.not(vertical_reviewed_at: nil)
      .where(achievement_submission_rows: { action_plan_row_id: row_ids, month: @selected_month })
      .includes(achievement_submission_rows: :action_plan_row)
      .distinct

    submissions.each do |submission|
      rows_to_remove = submission.achievement_submission_rows.select do |submission_row|
        row_ids.include?(submission_row.action_plan_row_id) && submission_row.month == @selected_month
      end
      next if rows_to_remove.blank?

      if rows_to_remove.size == submission.achievement_submission_rows.size
        submission.update!(status: "superseded")
      else
        rows_to_remove.each(&:destroy!)
        refresh_submission_theme_ids!(submission)
      end
    end
  end

  def refresh_submission_theme_ids!(submission)
    theme_ids = submission.achievement_submission_rows.reload.map do |submission_row|
      ActionPlanRow.format_decimal_string(submission_row.action_plan_row.asa_theme_id)
    end.compact_blank.uniq.sort_by { |theme_id| theme_id.to_f }

    submission.update!(asa_theme_id: theme_ids.join(",")) if theme_ids.present?
  end

  def unresolved_returned_submissions(scope)
    scope.to_a.reject { |submission| newer_submission_exists_for?(submission) }
  end

  def newer_submission_exists_for?(submission)
    row_ids = submission.achievement_submission_rows.map(&:action_plan_row_id)
    return false if row_ids.blank?

    AchievementSubmission
      .for_rows(row_ids, submission.month)
      .where.not(id: submission.id)
      .where(
        "achievement_submissions.submitted_at > :submitted_at OR " \
          "(achievement_submissions.submitted_at = :submitted_at AND achievement_submissions.id > :id)",
        submitted_at: submission.submitted_at,
        id: submission.id
      )
      .exists?
  end

  def returned_entry_contexts_for(submissions)
    contexts_by_selection = {}

    submissions.each_with_object({}) do |submission, contexts|
      key = [
        submission.to_id.to_s,
        submission.project_name.to_s,
        submission.month.to_s
      ]
      contexts[submission.id] = contexts_by_selection[key] ||= returned_entry_context_for(submission)
    end
  end

  def returned_entry_context_for(submission)
    month = submission.month.to_s
    rows = @scoped_rows
      .where(to_id: submission.to_id, project_name: submission.project_name)
      .order(:asa_theme_id, :asa_activity_id, :activity_id, :id)
      .to_a
    row_ids = rows.map(&:id)
    locked_row_ids = locked_submission_row_ids_for(row_ids, month)
    active_row_ids = active_submission_row_ids_for(row_ids, month)
    returned_submissions = unresolved_returned_submissions(
      AchievementSubmission
        .returned_for_rows(row_ids, month)
        .includes(:vertical_approver, :po_approver, :coo_approver, :director_approver, achievement_submission_rows: :action_plan_row)
        .order(submitted_at: :desc, id: :desc)
    )

    {
      rows: rows,
      selected_to_id: submission.to_id,
      selected_to_label: [ submission.to_name, submission.to_id ].compact_blank.join(" / "),
      selected_project: submission.project_name,
      selected_month: month,
      target_rows_count: rows.count { |row| row.public_send(month).to_i.positive? },
      entry_details_by_row_id: row_ids.present? ? AchievementEntryDetail.for_rows(row_ids, month) : {},
      locked_submission_row_ids: locked_row_ids,
      editable_row_count: row_ids.size - locked_row_ids.size,
      submission_candidate_row_count: (row_ids - active_row_ids).size,
      locked_submission_count: row_ids.present? ? AchievementSubmission.locked_for_rows(row_ids, month).count : 0,
      active_submission_count: row_ids.present? ? AchievementSubmission.active_for_rows(row_ids, month).count : 0,
      selected_returned_submissions: returned_submissions
    }
  end

  def achievement_entry_csv
    CSV.generate(headers: true) do |csv|
      headers = [ "Project", "TO ID", "TO Name", "ASA Theme ID", "ASA Theme", "ASA Activity ID", "ASA Activity", "Project Activity", "Unit", "#{@selected_month.to_s.capitalize} Target", "#{@selected_month.to_s.capitalize} Achievement", "Remark" ]
      headers.unshift(ACHIEVEMENT_ROW_ID_HEADER) if current_user.admin?
      csv << headers

      @rows.each do |row|
        detail = @entry_details_by_row_id[row.id]
        values = [
          row.project_name,
          row.to_id,
          row.to_name,
          ActionPlanRow.format_decimal_string(row.asa_theme_id),
          row.asa_theme,
          ActionPlanRow.format_decimal_string(row.asa_activity_id),
          row.asa_activity_name,
          row.activity.presence || row.activity_id,
          row.unit_type,
          @selected_month.present? ? row.public_send(@selected_month).to_i : nil,
          @selected_month.present? ? row.public_send("#{@selected_month}_t").to_i : nil,
          detail&.remark
        ]
        values.unshift(row.id) if current_user.admin?
        csv << values
      end
    end
  end
end

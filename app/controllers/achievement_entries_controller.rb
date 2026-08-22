require "csv"

class AchievementEntriesController < ApplicationController
  before_action :require_login
  before_action :set_fco_context

  MONTH_OPTIONS = ActionPlanRow::MONTH_COLUMNS.map { |month| [ month.capitalize, month ] }.freeze

  def show
    # Opening Achievement Entry from menu (no filters) must start blank.
    # Ignore leftover query params unless user explicitly chose filters.
    if params[:to_id].blank? && params[:project].blank? && params[:month].blank?
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

    if @selected_to_id.blank? || @selected_project.blank? || @selected_month.blank?
      redirect_to achievement_entry_path, alert: "Please choose TO, project and month."
      return
    end

    if selected_rows_locked?
      redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
        alert: "Vertical approval is done for one or more rows. Achievement changes are locked."
      return
    end

    unless ActionPlanRow::MONTH_COLUMNS.include?(@selected_month)
      redirect_to achievement_entry_path, alert: "Please choose a valid month."
      return
    end

    save_achievement_values!
    save_entry_details!
    load_selection

    if params[:commit].to_s == "Submit for Approval"
      created_count = create_achievement_submissions!
      redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
        notice: "#{created_count} achievement approval request#{'s' unless created_count == 1} submitted."
      return
    end

    redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
      notice: "Achievement rows, remarks and files saved for #{@selected_month.capitalize}."
  rescue ActiveRecord::RecordInvalid => error
    action = params[:commit].to_s == "Submit for Approval" ? "Submit" : "Save"
    redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
      alert: "#{action} failed: #{error.record.errors.full_messages.to_sentence}"
  end

  def submit
    load_selection

    if @rows.blank?
      redirect_to achievement_entry_path, alert: "Choose TO, project and month before submitting."
      return
    end

    if selected_rows_locked?
      redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
        alert: "These achievements are already locked after vertical approval."
      return
    end

    save_achievement_values!
    save_entry_details!
    load_selection
    created_count = create_achievement_submissions!

    redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
      notice: "#{created_count} achievement approval request#{'s' unless created_count == 1} submitted."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
      alert: "Submit failed: #{error.record.errors.full_messages.to_sentence}"
  end

  private

  def set_fco_context
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
    @fco_ids = @fco_mappings.pluck(:fco_id).flat_map { |fco_id| ActionPlanFcoGroup.ids_for(fco_id) }.uniq
    @scoped_rows = ActionPlanRow.active_import.where(user_id: @fco_ids)

    @to_options = @scoped_rows
      .where.not(to_id: [ nil, "" ])
      .distinct
      .order(:to_name, :to_id)
      .pluck(:to_name, :to_id)
      .map { |to_name, to_id| [ to_name.presence || "TO #{to_id}", to_id.to_s ] }

    @selected_to_id = selected_value(params[:to_id], @to_options.map(&:last))
    to_rows = @selected_to_id.present? ? @scoped_rows.where(to_id: @selected_to_id) : @scoped_rows.none

    @project_options = if @selected_to_id.present?
      to_rows
        .where.not(project_name: [ nil, "" ])
        .distinct
        .order(:project_name)
        .pluck(:project_name)
    else
      []
    end

    @selected_project = selected_value(params[:project], @project_options)
    @selected_month = selected_value(params[:month], ActionPlanRow::MONTH_COLUMNS)

    @rows = if @selected_to_id.present? && @selected_project.present? && @selected_month.present?
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
    @locked_submission_count = if @rows.present? && @selected_month.present? && selected_rows_locked?
      AchievementSubmission.locked_for_rows(@rows.map(&:id), @selected_month).count
    else
      0
    end
    @active_submission_count = if @rows.present? && @selected_month.present?
      AchievementSubmission.active_for_rows(@rows.map(&:id), @selected_month).count
    else
      0
    end
  end

  # Never auto-pick the first dropdown option — user must choose explicitly.
  def selected_value(value, options)
    return if value.blank?

    options.find { |option| option.to_s == value.to_s }
  end

  def clean_achievement_value(value)
    Integer(value.presence || 0, exception: false).to_i.clamp(0, 2_147_483_647)
  end

  def save_achievement_values!
    achievement_column = "#{@selected_month}_t"
    permitted_values = params[:achievements].respond_to?(:to_unsafe_h) ? params[:achievements].to_unsafe_h : {}
    accessible_rows = @scoped_rows.where(id: permitted_values.keys)

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
    accessible_ids = @scoped_rows.where(id: @rows.map(&:id)).pluck(:id)
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

  def create_achievement_submissions!
    row_ids = @rows.map(&:id)
    if AchievementSubmission.active_for_rows(row_ids, @selected_month).exists?
      raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
        submission.errors.add(:base, "Approval request already exists for this selected month/project.")
      end)
    end

    # Rows without ASA Theme ID cannot be routed to a vertical approver.
    # Keep them out of the approval package (achievements can still be saved as draft).
    submittable_rows = @rows.select { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id).present? }
    if submittable_rows.blank?
      raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
        submission.errors.add(:base, "No activities with ASA Theme ID found for approval. Check the action plan import.")
      end)
    end

    # One review per TO + vertical owner (all of that vertical's themes together).
    # Example: June / Palsud / Anurag = single request with themes 1,2,3,11,12 inside.
    state_codes = submittable_rows.map { |row| row.statte.to_s.squish.upcase }.uniq
    theme_ids = submittable_rows.map { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id) }.uniq
    mappings_by_key = ActionPlanVerticalMapping
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

    ownerships_by_po_project = ProjectOwnership
      .where(po_id: submittable_rows.map(&:po_id).uniq, project_name: submittable_rows.map(&:project_name).uniq)
      .index_by { |ownership| [ ownership.po_id, ownership.project_name ] }
    ownerships_by_po = ProjectOwnership.where(po_id: submittable_rows.map(&:po_id).uniq).index_by(&:po_id)
    ownerships_by_project = ProjectOwnership.where(project_name: submittable_rows.map(&:project_name).uniq).index_by(&:project_name)

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
        theme_ids = rows.map { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id) }.uniq.sort_by { |id| id.to_f }
        ownership = ownerships_by_po_project[[ sample.po_id, sample.project_name ]] ||
          ownerships_by_po[sample.po_id] ||
          ownerships_by_project[sample.project_name]

        submission = AchievementSubmission.create!(
          employee: @employee,
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

  def selected_rows_locked?
    @rows.present? && AchievementSubmission.locked_for_rows(@rows.map(&:id), @selected_month).exists?
  end

  def achievement_entry_csv
    CSV.generate(headers: true) do |csv|
      csv << [ "Project", "TO ID", "TO Name", "ASA Theme ID", "ASA Theme", "ASA Activity ID", "ASA Activity", "Project Activity", "Unit", "#{@selected_month.to_s.capitalize} Target", "#{@selected_month.to_s.capitalize} Achievement", "Remark" ]

      @rows.each do |row|
        detail = @entry_details_by_row_id[row.id]
        csv << [
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
      end
    end
  end
end

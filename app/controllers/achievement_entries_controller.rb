class AchievementEntriesController < ApplicationController
  before_action :require_login
  before_action :set_fco_context

  MONTH_OPTIONS = ActionPlanRow::MONTH_COLUMNS.map { |month| [ month.capitalize, month ] }.freeze

  def show
    load_selection
  end

  def update
    load_selection

    if selected_rows_locked?
      redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
        alert: "Vertical approval is done for one or more rows. Achievement changes are locked."
      return
    end

    unless ActionPlanRow::MONTH_COLUMNS.include?(@selected_month)
      redirect_to achievement_entry_path, alert: "Please choose a valid month."
      return
    end

    achievement_column = "#{@selected_month}_t"
    permitted_values = params[:achievements].respond_to?(:to_unsafe_h) ? params[:achievements].to_unsafe_h : {}
    accessible_rows = @scoped_rows.where(id: permitted_values.keys)

    updated_count = 0
    ActionPlanRow.transaction do
      accessible_rows.find_each do |row|
        value = clean_achievement_value(permitted_values[row.id.to_s])
        row.update!(achievement_column => value)
        updated_count += 1
      end
    end

    if params[:commit].to_s == "Submit for Approval"
      load_selection
      created_count = create_achievement_submissions!
      redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
        notice: "#{created_count} achievement approval request#{'s' unless created_count == 1} submitted."
      return
    end

    redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
      notice: "#{updated_count} achievement rows saved for #{@selected_month.capitalize}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to achievement_entry_path(to_id: @selected_to_id, project: @selected_project, month: @selected_month),
      alert: "Submit failed: #{error.record.errors.full_messages.to_sentence}"
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

    return if @fco_mappings.exists?

    redirect_to dashboard_path, alert: "No action plan FCO mapping found for this login."
  end

  def load_selection
    @month_options = MONTH_OPTIONS
    @fco_ids = @fco_mappings.pluck(:fco_id)
    @scoped_rows = ActionPlanRow.active_import.where(user_id: @fco_ids)

    @to_options = @scoped_rows
      .where.not(to_id: [ nil, "" ])
      .distinct
      .order(:to_name, :to_id)
      .pluck(:to_name, :to_id)
      .map { |to_name, to_id| [ to_name.presence || "TO #{to_id}", to_id ] }

    @selected_to_id = selected_value(params[:to_id], @to_options.map(&:last))
    to_rows = @selected_to_id.present? ? @scoped_rows.where(to_id: @selected_to_id) : @scoped_rows.none

    @project_options = to_rows
      .where.not(project_name: [ nil, "" ])
      .distinct
      .order(:project_name)
      .pluck(:project_name)

    @selected_project = selected_value(params[:project], @project_options)
    @selected_month = selected_value(params[:month], ActionPlanRow::MONTH_COLUMNS)

    @rows = if @selected_to_id.present? && @selected_project.present? && @selected_month.present?
      to_rows.where(project_name: @selected_project)
        .order(:asa_theme_id, :asa_activity_id, :activity_id, :id)
        .to_a
    else
      []
    end

    @target_total = @selected_month.present? ? @rows.sum { |row| row.public_send(@selected_month).to_i } : 0
    @achievement_total = @selected_month.present? ? @rows.sum { |row| row.public_send("#{@selected_month}_t").to_i } : 0
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

  # Only accept an explicit choice from the dropdown — never auto-pick the first option.
  def selected_value(value, options)
    return if value.blank?

    options.include?(value) ? value : nil
  end

  def clean_achievement_value(value)
    Integer(value.presence || 0, exception: false).to_i.clamp(0, 2_147_483_647)
  end

  def save_achievement_values!
    achievement_column = "#{@selected_month}_t"
    permitted_values = params[:achievements].respond_to?(:to_unsafe_h) ? params[:achievements].to_unsafe_h : {}
    accessible_rows = @scoped_rows.where(id: permitted_values.keys)

    accessible_rows.find_each do |row|
      row.update!(achievement_column => clean_achievement_value(permitted_values[row.id.to_s]))
    end

    load_selection
  end

  def create_achievement_submissions!
    row_ids = @rows.map(&:id)
    if AchievementSubmission.active_for_rows(row_ids, @selected_month).exists?
      raise ActiveRecord::RecordInvalid.new(AchievementSubmission.new.tap do |submission|
        submission.errors.add(:base, "Approval request already exists for this selected month/project.")
      end)
    end

    # One review per TO + vertical owner (all of that vertical's themes together).
    # Example: June / Palsud / Anurag = single request with themes 1,2,3,11,12 inside.
    mapping_by_row = {}
    @rows.each do |row|
      state_code = row.statte.to_s.squish.upcase
      asa_theme_id = ActionPlanRow.format_decimal_string(row.asa_theme_id)
      mapping_by_row[row.id] = ActionPlanVerticalMapping.find_by(state_code: state_code, asa_theme_id: asa_theme_id)
    end

    groups = @rows.group_by do |row|
      mapping = mapping_by_row[row.id]
      [
        row.project_name.to_s,
        row.to_id.to_s,
        row.statte.to_s.squish.upcase,
        mapping&.employee_id
      ]
    end
    created_count = 0

    AchievementSubmission.transaction do
      groups.each do |(project_name, _to_id, state_code, _vertical_employee_id), rows|
        sample = rows.first
        vertical_mapping = mapping_by_row[sample.id]
        theme_ids = rows.map { |row| ActionPlanRow.format_decimal_string(row.asa_theme_id) }.uniq.sort_by { |id| id.to_f }
        ownership = ProjectOwnership.find_by(po_id: sample.po_id, project_name: sample.project_name) ||
          ProjectOwnership.find_by(po_id: sample.po_id) ||
          ProjectOwnership.find_by(project_name: sample.project_name)

        submission = AchievementSubmission.create!(
          employee: @employee,
          fco_id: sample.user_id,
          fco_name: sample.user_name,
          to_id: sample.to_id,
          to_name: sample.to_name,
          project_name: project_name,
          po_id: sample.po_id,
          state_code: state_code,
          asa_theme_id: theme_ids.join(","),
          month: @selected_month,
          submission_remark: params[:submission_remark].to_s.strip,
          vertical_approver: vertical_mapping&.employee,
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

  def selected_rows_locked?
    @rows.present? && AchievementSubmission.locked_for_rows(@rows.map(&:id), @selected_month).exists?
  end
end

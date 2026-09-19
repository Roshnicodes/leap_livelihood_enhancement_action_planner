require "csv"

class BudgetUtilizationsController < ApplicationController
  before_action :require_login
  before_action :require_budget_utilization_edit_access, only: %i[update import]

  ALL_PROJECTS_VALUE = "all".freeze
  MONTH_OPTIONS = BudgetUtilization::MONTH_KEYS.map { |month| [ month.capitalize, month ] }.freeze
  MONTH_KEYS = BudgetUtilization::MONTH_KEYS

  def index
    load_budget_workspace

    respond_to do |format|
      format.html
      format.xlsx do
        if @selected_project.blank? || @selected_month.blank?
          redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "Please choose project and month."
        else
          send_data XlsxWorkbook.from_csv(
            budget_utilization_csv,
            title: "Budget Utilization",
            sheet_name: "Utilization",
            protected: true,
            unlocked_headers: [ "#{@selected_month.capitalize} Utilized" ]
          ),
            filename: budget_utilization_filename,
            type: XlsxWorkbook::CONTENT_TYPE
        end
      end
    end
  end

  def update
    load_budget_workspace

    if @selected_project.blank? || @selected_month.blank? || @all_projects_selected
      redirect_to budget_utilizations_path, alert: "Please choose project and month."
      return
    end

    if @submitted_locked
      redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "This budget utilization is already submitted. Changes are locked."
      return
    end

    final_submit = params[:commit].to_s == "Submit Final"
    if final_submit && !@has_draft
      redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "Please save draft first. After checking the draft, submit final."
      return
    end

    BudgetUtilization.transaction do
      params.fetch(:utilizations, {}).each_value do |row_params|
        attrs = row_params.permit(:project_name, :activity_name, :vertical_name, :bli_code, :planned_amount, :utilized_amount)
        utilization = BudgetUtilization.find_or_initialize_by(
          project_name: attrs[:project_name],
          bli_code: attrs[:bli_code].to_s,
          month: @selected_month
        )
        utilization.assign_attributes(
          activity_name: attrs[:activity_name],
          vertical_name: attrs[:vertical_name],
          planned_amount: decimal(attrs[:planned_amount]),
          utilized_amount: decimal(attrs[:utilized_amount]),
          updated_by: current_user,
          status: final_submit ? "submitted" : "draft",
          submitted_at: final_submit ? Time.current : nil,
          submitted_by: final_submit ? current_user : nil
        )
        utilization.save!
      end
    end

    notice = final_submit ? "Budget utilization submitted. Changes are now locked." : "Budget utilization draft saved. Review it, then submit final."
    redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: error.record.errors.full_messages.to_sentence
  end

  def import
    load_budget_workspace

    if @selected_project.blank? || @selected_month.blank?
      redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "Please choose project and month."
      return
    end

    if params[:budget_file].blank?
      redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "Please choose the updated Excel file."
      return
    end

    result = import_budget_utilization_file!(params[:budget_file])
    message = "#{result[:imported]} #{"row".pluralize(result[:imported])} imported as draft for #{@selected_month.capitalize}."
    message = "#{message} #{result[:skipped]} #{"row".pluralize(result[:skipped])} skipped." if result[:skipped].positive?

    redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), notice: message
  rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to budget_utilizations_path(project: @selected_project, month: @selected_month), alert: "Budget utilization import failed: #{error.message}"
  end

  private

  def require_budget_utilization_edit_access
    return if BudgetUtilization.finance_user?(current_user)

    redirect_to budget_utilizations_path(project: params[:project], month: params[:month]), alert: "Only Accounts can update budget utilization."
  end

  def load_budget_workspace
    @can_edit = BudgetUtilization.finance_user?(current_user)
    @month_options = MONTH_OPTIONS
    @project_options = activity_scope.where.not(project_name: [ nil, "" ]).distinct.order(:project_name).pluck(:project_name)
    @selected_project = selected_project_param
    @all_projects_selected = @selected_project == ALL_PROJECTS_VALUE
    @selected_month = params[:month].presence_in(MONTH_KEYS)
    @visible_months = visible_months_for(@selected_month)
    @prior_months = @visible_months[0...-1]
    @submitted_locked = selected_budget_scope.where(status: "submitted").exists?
    @has_draft = selected_budget_scope.where(status: "draft").exists?
    @selected_budget_status = if @submitted_locked
      "submitted"
    elsif @has_draft
      "draft"
    else
      "not_started"
    end
    @selected_budget_audit = selected_budget_audit
    @rows = if @selected_project.present? && @selected_month.present?
      budget_rows_for(@selected_project, @selected_month)
    else
      []
    end
    @project_total = @rows.sum { |row| row[:total_allocated].to_d }
    @month_total = @rows.sum { |row| row[:month_amount].to_d }
    @utilized_total = @rows.sum { |row| row[:utilized_amount].to_d }
    @expenditure_total = @rows.sum { |row| row[:total_expenditure].to_d }
    @remaining_total = @project_total - @expenditure_total
  end

  def selected_project_param
    value = params[:project].to_s
    return ALL_PROJECTS_VALUE if value == ALL_PROJECTS_VALUE && @project_options.any?

    value.presence_in(@project_options)
  end

  def activity_scope
    scope = BliActivity.active.with_single_bli_code
    return scope if @can_edit
    return scope.none if current_user.employee.blank?

    scope.where(employee_id: current_user.employee.id)
  end

  def visible_months_for(selected_month)
    return [] if selected_month.blank?

    index = MONTH_KEYS.index(selected_month)
    return [] unless index

    MONTH_KEYS[0..index]
  end

  def budget_rows_for(project_name, month)
    project_names = project_name == ALL_PROJECTS_VALUE ? @project_options : [ project_name ]
    budget_rows_for_projects(project_names, month)
  end

  def budget_rows_for_projects(project_names, month)
    project_names = Array(project_names).compact_blank
    return [] if project_names.blank?

    activities = activity_scope
      .where(project_name: project_names)
      .order(:project_name, :bli_code, :name, :activity_name, :vertical_name)
    months = visible_months_for(month)
    existing_scope = BudgetUtilization.with_single_bli_code.includes(:submitted_by, :updated_by).where(project_name: project_names, month: months)
    existing_scope = existing_scope.submitted unless @can_edit
    existing = existing_scope
      .group_by { |utilization| [ utilization.project_name, utilization.bli_code.to_s ] }

    activities
      .group_by { |activity| [ activity.project_name, activity.bli_code.to_s ] }
      .map do |(project, bli_code), grouped_activities|
        sample = grouped_activities.first
        total_allocated = grouped_activities.map { |activity| activity.allocated_fund.to_d }.max || 0
        project_bli_name = grouped_activities.map { |activity| activity.name.presence || activity.activity_name }.compact_blank.first
        vertical_name = sample.vertical_name
        month_amount = month_amount_for(total_allocated, vertical_name, month)
        by_month = (existing[[ project, bli_code ]] || []).index_by(&:month)

        month_utilized = months.index_with do |candidate|
          by_month[candidate]&.utilized_amount.to_d
        end
        month_audit = months.index_with do |candidate|
          budget_audit_line(by_month[candidate])
        end
        current = by_month[month]
        prior_expenditure = months[0...-1].sum { |candidate| month_utilized[candidate].to_d }
        current_utilized = current&.utilized_amount.to_d
        total_expenditure = prior_expenditure + current_utilized

        {
          project_name: project,
          project_id: project_id_for(
            project,
            fallback_texts: grouped_activities.map { |activity| activity.name.presence || activity.activity_name }
          ),
          activity_name: project_bli_name,
          vertical_name: vertical_name,
          bli_code: bli_code,
          project_bli_label: [ bli_code, project_bli_name ].compact_blank.join(" "),
          total_allocated: total_allocated,
          month_utilized: month_utilized,
          prior_expenditure: prior_expenditure,
          total_expenditure: total_expenditure,
          total_remaining: total_allocated - total_expenditure,
          month_amount: month_amount,
          utilized_amount: current_utilized,
          month_audit: month_audit,
          audit_line: budget_audit_line(current)
        }
      end
      .sort_by { |row| [ row[:project_name].to_s, bli_code_sort_key(row[:bli_code]), row[:activity_name].to_s ] }
  end

  def selected_budget_audit
    records = selected_budget_scope.includes(:submitted_by, :updated_by).to_a
    return {} if records.blank?

    latest_update = records.max_by(&:updated_at)
    submitted_records = records.select(&:submitted?)
    latest_submission = submitted_records.filter_map(&:submitted_at).max
    submitters = submitted_records.map { |record| user_label(record.submitted_by) }.reject { |label| label == "-" }.uniq

    {
      draft_saved_at: latest_update&.updated_at,
      draft_saved_by: user_label(latest_update&.updated_by),
      submitted_at: latest_submission,
      submitted_by: submitters.to_sentence
    }
  end

  def budget_audit_line(record)
    return if record.blank?

    if record.submitted?
      submitted_by = user_label(record.submitted_by)
      submitted_at = helpers.format_record_datetime(record.submitted_at)
      return "Submitted #{submitted_at} by #{submitted_by}"
    end

    updated_by = user_label(record.updated_by)
    updated_at = helpers.format_record_datetime(record.updated_at)
    "Draft updated #{updated_at} by #{updated_by}"
  end

  def user_label(user)
    return "-" if user.blank?

    employee = user.employee
    return [ employee.employee_code, employee.name ].compact_blank.join(" - ") if employee.present?

    user.login.presence || "User ##{user.id}"
  end

  def bli_code_sort_key(code)
    code.to_s.split(".").map { |part| part.to_i }
  end

  def month_amount_for(total_amount, vertical_name, month)
    percent = vertical_percent_for(vertical_name)
    if month == MONTH_KEYS.last
      earlier_months = MONTH_KEYS[0...-1].sum do |candidate|
        (total_amount * (percent&.public_send(candidate) || 0) / 100).round(2)
      end
      total_amount - earlier_months
    else
      (total_amount * (percent&.public_send(month) || 0) / 100).round(2)
    end
  end

  def vertical_percent_for(vertical_name)
    @vertical_percents_by_name ||= VerticalPercent.all.index_by(&:vertical_name)
    @vertical_percents_by_name[vertical_name]
  end

  def decimal(value)
    BigDecimal(value.to_s.presence || "0")
  rescue ArgumentError
    0
  end

  def selected_budget_scope
    return BudgetUtilization.none if @selected_project.blank? || @selected_month.blank?

    if @selected_project == ALL_PROJECTS_VALUE
      return BudgetUtilization.with_single_bli_code.where(project_name: @project_options, month: @selected_month)
    end

    BudgetUtilization.with_single_bli_code.where(project_name: @selected_project, month: @selected_month)
  end

  def import_budget_utilization_file!(file)
    month_header = "#{@selected_month.capitalize} Utilized"
    rows = SpreadsheetRows.read(file_path(file), sheet: :first, header_match: [ "Project", "Project BLI Code", month_header ])
    raise ArgumentError, "No utilization rows found in the uploaded sheet." if rows.blank?

    allowed_rows = budget_rows_for(@selected_project, @selected_month).index_by do |row|
      budget_import_key(row[:project_name], row[:bli_code])
    end
    result = { imported: 0, skipped: 0 }

    BudgetUtilization.transaction do
      rows.each do |row|
        project_name = spreadsheet_value(row, "Project")
        bli_code = spreadsheet_value(row, "Project BLI Code")
        next if project_name.blank? && bli_code.blank?

        target = allowed_rows[budget_import_key(project_name, bli_code)]
        if target.blank?
          result[:skipped] += 1
          next
        end

        utilization = BudgetUtilization.find_or_initialize_by(
          project_name: target[:project_name],
          bli_code: target[:bli_code].to_s,
          month: @selected_month
        )
        utilization.assign_attributes(
          activity_name: target[:activity_name],
          vertical_name: target[:vertical_name],
          planned_amount: target[:month_amount],
          utilized_amount: imported_utilized_amount(row, month_header),
          updated_by: current_user,
          status: "draft",
          submitted_at: nil,
          submitted_by: nil
        )
        utilization.save!
        result[:imported] += 1
      end
    end

    raise ArgumentError, "No matching rows found for selected project and month." if result[:imported].zero?

    result
  end

  def budget_import_key(project_name, bli_code)
    [ ActionPlanText.group_key(project_name), ActionPlanText.group_key(bli_code) ]
  end

  def imported_utilized_amount(row, month_header)
    decimal(spreadsheet_value(row, month_header).presence || 0)
  end

  def spreadsheet_value(row, *headers)
    normalized = row.transform_keys { |key| key.to_s.squish.downcase }
    headers.each do |header|
      value = normalized[header.to_s.squish.downcase]
      return value.to_s.squish if value.to_s.squish.present?
    end

    nil
  end

  def file_path(file)
    file.respond_to?(:path) ? file.path : file.to_s
  end

  def budget_utilization_csv
    CSV.generate(headers: true) do |csv|
      csv << budget_utilization_csv_headers

      @rows.each_with_index do |row, index|
        csv << [
          index + 1,
          row[:project_id],
          row[:project_name],
          row[:vertical_name],
          row[:bli_code],
          row[:activity_name],
          row[:project_bli_label],
          row[:total_allocated],
          row[:total_expenditure],
          row[:total_remaining],
          *@prior_months.map { |month| row[:month_utilized][month].to_d },
          row[:month_amount],
          row[:utilized_amount],
          row[:audit_line]
        ]
      end
    end
  end

  def budget_utilization_csv_headers
    [
      "S.No.",
      "Project ID",
      "Project",
      "Project P&B",
      "Project BLI Code",
      "Project BLI",
      "Project BLI Code Project BLI",
      "Total Allocated Budget",
      "Total Expenditure",
      "Total Remaining Budget",
      *@prior_months.map { |month| "#{month.capitalize} Utilized" },
      "#{@selected_month.capitalize} Planned Budget",
      "#{@selected_month.capitalize} Utilized",
      "#{@selected_month.capitalize} Details"
    ]
  end

  def budget_utilization_filename
    project_label = @selected_project == ALL_PROJECTS_VALUE ? "all_projects" : @selected_project.to_s.parameterize(separator: "_")
    "budget_utilization_#{project_label}_#{@selected_month}_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx"
  end

  def project_id_for(project_name, fallback_texts: [])
    key = ([ project_name ] + Array(fallback_texts)).map { |value| normalized_project_key(value) }.compact_blank.join("|")
    @project_id_cache ||= {}
    return @project_id_cache[key] if @project_id_cache.key?(key)

    exact_project_id =
      ProjectInformationSheet
        .where("LOWER(project_title) = :project OR LOWER(project_id) = :project", project: project_name.to_s.downcase)
        .pick(:project_id) ||
      ActionPlanRow
        .active_import
        .where(project_name: project_name)
        .where.not(project_id: [ nil, "" ])
        .pick(:project_id)

    @project_id_cache[key] =
      exact_project_id ||
      lookup_project_id_by_label(project_name) ||
      Array(fallback_texts).filter_map { |label| lookup_project_id_by_label(label) }.first
  end

  def lookup_project_id_by_label(label)
    key = normalized_project_key(label)
    return if key.blank?

    exact = project_id_candidates.find { |candidate| candidate[:key] == key }
    return exact[:project_id] if exact

    contained = project_id_candidates.find do |candidate|
      candidate[:key].length >= 5 && (key.include?(candidate[:key]) || candidate[:key].include?(key))
    end
    return contained[:project_id] if contained

    token_matches = project_id_candidates.select do |candidate|
      first_project_token(label).present? && candidate[:tokens].include?(first_project_token(label))
    end
    return token_matches.first[:project_id] if token_matches.one?

    close = project_id_candidates.find do |candidate|
      key.length >= 12 && candidate[:key].length >= 12 && edit_distance(key, candidate[:key]) <= 2
    end
    close&.fetch(:project_id)
  end

  def project_id_candidates
    @project_id_candidates ||= begin
      pis_candidates = ProjectInformationSheet
        .where.not(project_id: [ nil, "" ])
        .pluck(:project_id, :project_title)
      action_plan_candidates = ActionPlanRow
        .active_import
        .where.not(project_id: [ nil, "" ])
        .distinct
        .pluck(:project_id, :project_name)

      (pis_candidates + action_plan_candidates).filter_map do |project_id, label|
        key = normalized_project_key(label)
        next if key.blank?

        {
          project_id: project_id.to_s,
          key: key,
          tokens: project_tokens(label)
        }
      end
    end
  end

  def normalized_project_key(value)
    ActionPlanText.group_key(value).gsub(/[^a-z0-9]+/, "")
  end

  def project_tokens(value)
    ActionPlanText.group_key(value).split(/[^a-z0-9]+/).select { |token| token.length >= 4 }
  end

  def first_project_token(value)
    project_tokens(value).first
  end

  def edit_distance(left, right)
    previous = (0..right.length).to_a

    left.chars.each_with_index do |left_char, left_index|
      current = [ left_index + 1 ]
      right.chars.each_with_index do |right_char, right_index|
        cost = left_char == right_char ? 0 : 1
        current << [
          current[right_index] + 1,
          previous[right_index + 1] + 1,
          previous[right_index] + cost
        ].min
      end
      previous = current
    end

    previous[right.length]
  end
end

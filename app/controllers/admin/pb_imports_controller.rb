module Admin
  class PbImportsController < ApplicationController
    BLI_ACTIVITY_FORM_ATTRIBUTES = [
      :employee_id,
      :stakeholder_name,
      :allocating_date,
      :name,
      :bli_code,
      :allocated_fund,
      :remaining_fund,
      :financial_year,
      :project_name,
      :office_name,
      :vertical_name,
      :parent_activity,
      :activity_name,
      :responsible_user_name,
      :utilised_fund,
      :approved_utilised_fund,
      :total_pdo_count,
      :total_pdo_amount,
      :approved_pdo_count,
      :approved_pdo_amount,
      :pending_pdo_count,
      :pending_pdo_amount,
      :total_rfp_count,
      :total_rfp_amount,
      :approved_rfp_count,
      :approved_rfp_amount,
      :pending_rfp_count,
      :pending_rfp_amount
    ].freeze
    MONEY_ATTRIBUTES = %i[
      allocated_fund
      remaining_fund
      utilised_fund
      approved_utilised_fund
      total_pdo_amount
      approved_pdo_amount
      pending_pdo_amount
      total_rfp_amount
      approved_rfp_amount
      pending_rfp_amount
    ].freeze
    COUNT_ATTRIBUTES = %i[
      total_pdo_count
      approved_pdo_count
      pending_pdo_count
      total_rfp_count
      approved_rfp_count
      pending_rfp_count
    ].freeze
    PARENT_ACTIVITY_ASSIGNMENT_FORM_ATTRIBUTES = %i[source_parent_activity employee_id vertical_percent_id].freeze

    before_action :require_login
    before_action :require_admin
    before_action :set_bli_activity, only: %i[update_bli_activity toggle_bli_activity]
    before_action :set_parent_activity_assignment, only: %i[update_parent_activity_assignment toggle_parent_activity_assignment]

    def index
      load_pb_import_context
    end

    def download
      filename = "pb_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx"
      send_data PbActivityExporter.active_xlsx,
        filename: filename,
        type: PbActivityExporter::XLSX_CONTENT_TYPE
    end

    def download_file
      import_file = PbImportFile.find(params[:id])

      unless import_file.file_available?
        redirect_to admin_pb_imports_path, alert: "Saved file is missing from storage."
        return
      end

      send_file import_file.absolute_path,
        filename: import_file.original_filename,
        type: import_file.content_type.presence || "application/octet-stream",
        disposition: "attachment"
    end

    def create
      if params[:pb_file].blank? && params[:parent_activity_file].blank?
        redirect_to admin_pb_imports_path, alert: "Please choose a P&B source file or parent activity mapping file to import."
        return
      end

      backup_active_pb_if_needed
      saved_mapping_file = capture_parent_activity_mapping
      saved_source_file = capture_pb_source
      sync_source_file = saved_source_file || PbImportFile.latest_source
      clear_summaries = false

      mapping_count = import_parent_activity_mapping(saved_mapping_file)
      source_row_count = import_pb_source(sync_source_file, clear_summaries: clear_summaries) if sync_source_file && (saved_source_file || saved_mapping_file)

      saved_source_file&.mark_imported!(source_row_count)

      redirect_to admin_pb_imports_path, notice: import_message(mapping_count: mapping_count, source_row_count: source_row_count, clear_summaries: clear_summaries)
    rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
      saved_mapping_file&.mark_failed!(error.message)
      saved_source_file&.mark_failed!(error.message)
      redirect_to admin_pb_imports_path, alert: "P&B import failed: #{error.message}"
    end

    def create_bli_activity
      activity = BliActivity.new(bli_activity_params)
      prepare_bli_activity!(activity)
      activity.import_flag = 0
      activity.active = true
      activity.save!

      redirect_to admin_pb_imports_path(anchor: "pb-main-file"),
        notice: "P&B row added."
    rescue ActiveRecord::RecordInvalid => error
      load_pb_import_context(bli_activity_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update_bli_activity
      @bli_activity.assign_attributes(bli_activity_params)
      prepare_bli_activity!(@bli_activity)
      @bli_activity.save!

      redirect_to admin_pb_imports_path(anchor: "pb-main-file"),
        notice: "P&B row updated."
    rescue ActiveRecord::RecordInvalid => error
      load_pb_import_context(bli_activity_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_bli_activity
      @bli_activity.update!(active: !@bli_activity.active?)

      redirect_to admin_pb_imports_path(anchor: "pb-main-file"),
        notice: "P&B row #{@bli_activity.active? ? "enabled" : "disabled"}."
    end

    def create_parent_activity_assignment
      assignment = ParentActivityAssignment.find_or_initialize_by(
        source_parent_activity: parent_activity_assignment_params[:source_parent_activity]
      )
      assignment.assign_attributes(parent_activity_assignment_params)
      assignment.active = true
      assignment.save!
      sync_employee_vertical_mapping_for(assignment)

      redirect_to admin_pb_imports_path(anchor: "parent-activity-mapping"),
        notice: "Parent activity mapping saved."
    rescue ActiveRecord::RecordInvalid => error
      load_pb_import_context(parent_activity_assignment_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update_parent_activity_assignment
      previous_employee_id = @parent_activity_assignment.employee_id
      previous_vertical_percent_id = @parent_activity_assignment.vertical_percent_id
      @parent_activity_assignment.assign_attributes(parent_activity_assignment_params)
      @parent_activity_assignment.save!
      sync_employee_vertical_mapping_for(@parent_activity_assignment)
      disable_employee_vertical_mapping_unless_used(previous_employee_id, previous_vertical_percent_id)

      redirect_to admin_pb_imports_path(anchor: "parent-activity-mapping"),
        notice: "Parent activity mapping updated."
    rescue ActiveRecord::RecordInvalid => error
      load_pb_import_context(parent_activity_assignment_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_parent_activity_assignment
      @parent_activity_assignment.update!(active: !@parent_activity_assignment.active?)
      sync_employee_vertical_mapping_for(@parent_activity_assignment)

      redirect_to admin_pb_imports_path(anchor: "parent-activity-mapping"),
        notice: "Parent activity mapping #{@parent_activity_assignment.active? ? "enabled" : "disabled"}."
    end

    private

    def load_pb_import_context(bli_activity_form: nil, parent_activity_assignment_form: nil)
      @import_files = PbImportFile.recent.limit(30)
      @latest_imported_at = PbImportFile.imported.where(file_kind: "source").recent.first&.imported_at
      @bli_activities = BliActivity
        .current_import
        .includes(:employee)
        .order(active: :desc, project_name: :asc, vertical_name: :asc, bli_code: :asc, id: :asc)
      @parent_activity_assignments = ParentActivityAssignment
        .includes(:employee, :vertical_percent)
        .order(active: :desc, source_parent_activity: :asc)
      @employee_options = Employee.order(:name, :employee_code)
      @vertical_percent_options = VerticalPercent.order(:vertical_name)
      @summary = {
        activities: BliActivity.active.count,
        disabled_activities: BliActivity.disabled.count,
        archived_activities: BliActivity.archived_import.count,
        projects: BliActivity.active.distinct.count(:project_name),
        verticals: BliActivity.active.distinct.count(:vertical_name),
        allocated: BliActivity.active.sum(:allocated_fund),
        parent_mappings: ParentActivityAssignment.active.count,
        disabled_parent_mappings: ParentActivityAssignment.disabled.count,
        import_files: @import_files.size
      }
      @bli_activity_form = bli_activity_form ||
        BliActivity.current_import.find_by(id: params[:edit_bli_activity_id]) ||
        BliActivity.new(import_flag: 0, active: true, financial_year: PbImportFile.financial_year_for)
      @parent_activity_assignment_form = parent_activity_assignment_form ||
        ParentActivityAssignment.includes(:employee, :vertical_percent).find_by(id: params[:edit_parent_activity_assignment_id]) ||
        ParentActivityAssignment.new(active: true)
    end

    def set_bli_activity
      @bli_activity = BliActivity.current_import.find(params[:id])
    end

    def set_parent_activity_assignment
      @parent_activity_assignment = ParentActivityAssignment.find(params[:id])
    end

    def bli_activity_params
      params.require(:bli_activity).permit(*BLI_ACTIVITY_FORM_ATTRIBUTES).tap do |attributes|
        attributes[:financial_year] = attributes[:financial_year].to_s.squish
        attributes[:project_name] = attributes[:project_name].to_s.squish
        attributes[:vertical_name] = attributes[:vertical_name].to_s.squish
        attributes[:parent_activity] = attributes[:parent_activity].to_s.squish
        attributes[:activity_name] = attributes[:activity_name].to_s.squish
        attributes[:responsible_user_name] = attributes[:responsible_user_name].to_s.squish
        attributes[:bli_code] = attributes[:bli_code].to_s.squish
      end
    end

    def parent_activity_assignment_params
      params.require(:parent_activity_assignment)
        .permit(*PARENT_ACTIVITY_ASSIGNMENT_FORM_ATTRIBUTES)
        .tap { |attributes| attributes[:source_parent_activity] = attributes[:source_parent_activity].to_s.squish }
    end

    def prepare_bli_activity!(activity)
      activity.financial_year = PbImportFile.financial_year_for if activity.financial_year.blank?
      activity.responsible_user_name = activity.employee&.name if activity.responsible_user_name.blank?
      activity.parent_activity = activity.vertical_name if activity.parent_activity.blank?
      remaining_fund_blank = activity.remaining_fund.blank?

      MONEY_ATTRIBUTES.each do |attribute|
        activity.public_send("#{attribute}=", decimal_value(activity.public_send(attribute)))
      end
      COUNT_ATTRIBUTES.each do |attribute|
        activity.public_send("#{attribute}=", activity.public_send(attribute).to_i)
      end

      activity.remaining_fund = activity.allocated_fund if remaining_fund_blank
    end

    def decimal_value(raw)
      return raw if raw.is_a?(Numeric)

      BigDecimal(raw.to_s.gsub(/[^0-9.-]/, "").presence || "0")
    rescue ArgumentError
      0
    end

    def sync_employee_vertical_mapping_for(assignment)
      if assignment.active?
        mapping = EmployeeVerticalMapping.find_or_initialize_by(
          employee: assignment.employee,
          vertical_percent: assignment.vertical_percent
        )
        mapping.active = true
        mapping.save!
      else
        disable_employee_vertical_mapping_unless_used(assignment.employee_id, assignment.vertical_percent_id)
      end
    end

    def disable_employee_vertical_mapping_unless_used(employee_id, vertical_percent_id)
      return if employee_id.blank? || vertical_percent_id.blank?
      return if ParentActivityAssignment.active.where(employee_id: employee_id, vertical_percent_id: vertical_percent_id).exists?

      EmployeeVerticalMapping
        .where(employee_id: employee_id, vertical_percent_id: vertical_percent_id)
        .update_all(active: false, updated_at: Time.current)
    end

    def capture_parent_activity_mapping
      return if params[:parent_activity_file].blank?

      PbImportFile.capture!(upload: params[:parent_activity_file], uploaded_by: current_user, file_kind: "parent_activity_mapping")
    end

    def capture_pb_source
      return if params[:pb_file].blank?

      PbImportFile.capture!(upload: params[:pb_file], uploaded_by: current_user)
    end

    def backup_active_pb_if_needed
      return unless params[:pb_file].present? || (params[:parent_activity_file].present? && PbImportFile.latest_source.present?)

      PbImportFile.capture_active_snapshot!(uploaded_by: current_user)
    end

    def import_parent_activity_mapping(saved_mapping_file)
      return unless saved_mapping_file

      imported = ParentActivityAssignmentImporter.new(file_path: saved_mapping_file.absolute_path.to_s).import!
      saved_mapping_file.mark_imported!(imported)
      imported
    end

    def import_pb_source(sync_source_file, clear_summaries:)
      BliActivitySync.new(source_path: sync_source_file.absolute_path.to_s, save_history: false).call(clear_summaries: clear_summaries)
    end

    def import_message(mapping_count:, source_row_count:, clear_summaries:)
      messages = []
      messages << "#{mapping_count} parent activity mappings imported" if mapping_count
      messages << "#{source_row_count} P&B activities synced" if source_row_count
      messages << "old P&B summary submissions cleared" if clear_summaries
      messages << "previous active P&B file saved in history" if params[:pb_file].present?
      messages.join(", ").presence || "P&B import completed."
    end
  end
end

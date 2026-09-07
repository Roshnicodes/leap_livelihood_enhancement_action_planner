module Admin
  class ActionPlanFcoMappingsController < ApplicationController
    require "csv"

    before_action :require_login
    before_action :require_admin
    before_action :set_mapping, only: %i[update_mapping toggle_active destroy]

    def index
      load_mapping_context

      respond_to do |format|
        format.html
        format.csv do
          send_data fco_mappings_csv,
            filename: "action_plan_fco_mappings_#{Time.current.strftime("%Y%m%d_%H%M%S")}.csv",
            type: "text/csv; charset=utf-8"
        end
        format.xlsx do
          send_data fco_mappings_xlsx,
            filename: "action_plan_fco_mappings_#{Time.current.strftime("%Y%m%d_%H%M%S")}.xlsx",
            type: XlsxWorkbook::CONTENT_TYPE
        end
      end
    end

    def update
      @selected_employee = Employee.find(params[:employee_id])
      selected_fco_ids = Array(params[:fco_ids]).map(&:to_s).map(&:squish).compact_blank.uniq
      fcos_by_id = ActionPlanFcoMapping.action_plan_fcos.index_by { |fco| fco[:fco_id] }

      ActionPlanFcoMapping.transaction do
        existing_mappings = @selected_employee.action_plan_fco_mappings
        disabled_scope = selected_fco_ids.any? ? existing_mappings.where.not(fco_id: selected_fco_ids) : existing_mappings
        disabled_scope.update_all(active: false, updated_at: Time.current)

        selected_fco_ids.each do |fco_id|
          fco = fcos_by_id[fco_id]
          next unless fco

          mapping = ActionPlanFcoMapping.find_or_initialize_by(employee: @selected_employee, fco_id: fco_id)
          mapping.employee_code = @selected_employee.employee_code
          mapping.fco_name = fco[:fco_name]
          mapping.active = true
          mapping.save!
        end

        ActionPlanFcoMapping.enable_login_for!(@selected_employee) if selected_fco_ids.any?
      end

      redirect_to admin_action_plan_fco_mapping_path(employee_id: @selected_employee.id),
        notice: "#{@selected_employee.name} FCO access updated."
    end

    def import
      if params[:mapping_file].blank?
        redirect_to admin_action_plan_fco_mapping_path, alert: "Please choose FCO mapping file."
        return
      end

      result = ActionPlanFcoMapping.import_file!(params[:mapping_file].path)
      message = "#{result[:imported]} FCO mappings imported."
      message += " Skipped #{result[:skipped].size}: #{result[:skipped].first(5).join('; ')}" if result[:skipped].any?

      redirect_to admin_action_plan_fco_mapping_path, notice: message
    rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
      redirect_to admin_action_plan_fco_mapping_path, alert: "FCO mapping import failed: #{error.message}"
    end

    def create
      mapping = ActionPlanFcoMapping.new
      save_mapping!(mapping)

      redirect_to admin_action_plan_fco_mapping_path(employee_id: mapping.employee_id),
        notice: "#{mapping.employee&.name} FCO access added."
    rescue ActiveRecord::RecordInvalid => error
      load_mapping_context(mapping_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update_mapping
      save_mapping!(@mapping)

      redirect_to admin_action_plan_fco_mapping_path(employee_id: @mapping.employee_id),
        notice: "#{@mapping.employee&.name} FCO access updated."
    rescue ActiveRecord::RecordInvalid => error
      load_mapping_context(mapping_form: error.record)
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_active
      @mapping.update!(active: !@mapping.active?)
      ActionPlanFcoMapping.enable_login_for!(@mapping.employee) if @mapping.active?

      redirect_to admin_action_plan_fco_mapping_path(employee_id: @mapping.employee_id),
        notice: "#{@mapping.fco_name} access #{@mapping.active? ? "enabled" : "disabled"}."
    end

    def destroy
      @mapping.update!(active: false)

      redirect_to admin_action_plan_fco_mapping_path(employee_id: @mapping.employee_id),
        notice: "#{@mapping.employee&.name} - #{@mapping.fco_name} access disabled."
    end

    private

    def load_mapping_context(mapping_form: nil)
      @employees = Employee.order(:name)
      @selected_employee = selected_employee
      @fco_options = ActionPlanFcoMapping.action_plan_fcos
      @selected_fco_ids = @selected_employee ? @selected_employee.action_plan_fco_mappings.active.pluck(:fco_id) : []
      @mapping_rows = ActionPlanFcoMapping
        .joins(:employee)
        .includes(:employee)
        .order("action_plan_fco_mappings.active DESC, employees.name ASC, action_plan_fco_mappings.fco_name ASC, action_plan_fco_mappings.fco_id ASC")
      @active_mapping_rows = @mapping_rows.select(&:active?)
      @disabled_mapping_rows = @mapping_rows.reject(&:active?)
      @mapped_employees = @active_mapping_rows.map(&:employee).uniq
      @mapping_form = mapping_form || ActionPlanFcoMapping.includes(:employee).find_by(id: params[:edit_mapping_id]) || ActionPlanFcoMapping.new(active: true, employee: @selected_employee)
    end

    def selected_employee
      return Employee.find_by(id: params[:employee_id]) if params[:employee_id].present?

      Employee.order(:name).first
    end

    def fco_mappings_csv
      CSV.generate(headers: true) do |csv|
        csv << [ "Employee Code", "Employee Name", "FCO ID", "FCO Name", "Status" ]

        @mapping_rows.each do |mapping|
          csv << [
            mapping.employee_code,
            mapping.employee&.name,
            mapping.fco_id,
            mapping.fco_name,
            mapping.active? ? "Active" : "Disabled"
          ]
        end
      end
    end

    def fco_mappings_xlsx
      XlsxWorkbook.new([
        {
          name: "FCO Mapping",
          title: "Action Plan FCO Mapping",
          headers: [ "Employee Code", "Employee Name", "FCO ID", "FCO Name", "Status" ],
          rows: @mapping_rows.map do |mapping|
            [
              mapping.employee_code,
              mapping.employee&.name,
              mapping.fco_id,
              mapping.fco_name,
              mapping.active? ? "Active" : "Disabled"
            ]
          end,
          widths: [ 18, 32, 12, 30, 14 ]
        }
      ]).to_xlsx
    end

    def set_mapping
      @mapping = ActionPlanFcoMapping.includes(:employee).find(params[:id])
    end

    def save_mapping!(mapping)
      attributes = fco_mapping_params
      employee = Employee.find(attributes.delete(:employee_id))
      fco = ActionPlanFcoMapping.action_plan_fcos.find { |option| option[:fco_id] == attributes[:fco_id].to_s.squish }

      mapping.assign_attributes(attributes)
      mapping.employee = employee
      mapping.employee_code = employee.employee_code
      mapping.fco_name = mapping.fco_name.presence || fco&.fetch(:fco_name)
      mapping.active = true
      mapping.save!
      ActionPlanFcoMapping.enable_login_for!(employee)
    end

    def fco_mapping_params
      params.require(:action_plan_fco_mapping).permit(:employee_id, :fco_id, :fco_name).to_h
    end
  end
end

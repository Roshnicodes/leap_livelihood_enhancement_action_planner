module Admin
  class ActionPlanFcoMappingsController < ApplicationController
    require "csv"

    before_action :require_login
    before_action :require_admin

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
        @selected_employee.action_plan_fco_mappings.where.not(fco_id: selected_fco_ids).destroy_all

        selected_fco_ids.each do |fco_id|
          fco = fcos_by_id[fco_id]
          next unless fco

          ActionPlanFcoMapping.find_or_create_by!(employee: @selected_employee, fco_id: fco_id) do |mapping|
            mapping.employee_code = @selected_employee.employee_code
            mapping.fco_name = fco[:fco_name]
          end
        end
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

    def destroy
      mapping = ActionPlanFcoMapping.includes(:employee).find(params[:id])
      employee_id = mapping.employee_id
      label = "#{mapping.employee&.name} - #{mapping.fco_name}"
      mapping.destroy!

      redirect_to admin_action_plan_fco_mapping_path(employee_id: employee_id),
        notice: "#{label} access removed."
    end

    private

    def load_mapping_context
      @employees = Employee.order(:name)
      @selected_employee = selected_employee
      @fco_options = ActionPlanFcoMapping.action_plan_fcos
      @selected_fco_ids = @selected_employee ? @selected_employee.action_plan_fco_mappings.pluck(:fco_id) : []
      @mapping_rows = ActionPlanFcoMapping
        .joins(:employee)
        .includes(:employee)
        .order("employees.name ASC, action_plan_fco_mappings.fco_name ASC, action_plan_fco_mappings.fco_id ASC")
      @mapped_employees = @mapping_rows.map(&:employee).uniq
    end

    def selected_employee
      return Employee.find_by(id: params[:employee_id]) if params[:employee_id].present?

      Employee.order(:name).first
    end

    def fco_mappings_csv
      CSV.generate(headers: true) do |csv|
        csv << [ "Employee Code", "Employee Name", "FCO ID", "FCO Name" ]

        @mapping_rows.each do |mapping|
          csv << [
            mapping.employee_code,
            mapping.employee&.name,
            mapping.fco_id,
            mapping.fco_name
          ]
        end
      end
    end

    def fco_mappings_xlsx
      XlsxWorkbook.new([
        {
          name: "FCO Mapping",
          title: "Action Plan FCO Mapping",
          headers: [ "Employee Code", "Employee Name", "FCO ID", "FCO Name" ],
          rows: @mapping_rows.map do |mapping|
            [
              mapping.employee_code,
              mapping.employee&.name,
              mapping.fco_id,
              mapping.fco_name
            ]
          end,
          widths: [ 18, 32, 12, 30 ]
        }
      ]).to_xlsx
    end
  end
end

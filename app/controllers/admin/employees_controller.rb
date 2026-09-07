module Admin
  class EmployeesController < ApplicationController
    before_action :require_login
    before_action :require_admin
    before_action :set_employee, only: %i[update toggle_active]

    def index
      load_employee_context
    end

    def create
      @employee_form = Employee.new(employee_params)

      Employee.transaction do
        @employee_form.save!
        sync_employee_login!(@employee_form)
      end

      redirect_to admin_employees_path, notice: "#{@employee_form.name} added."
    rescue ActiveRecord::RecordInvalid => error
      form_employee = employee_form_after_error(error, @employee_form)
      load_employee_context(form_employee: form_employee)
      flash.now[:alert] = form_employee.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def update
      old_code = @employee.employee_code

      Employee.transaction do
        @employee.update!(employee_params)
        sync_employee_code_references!(old_code, @employee) if old_code != @employee.employee_code
        sync_employee_login!(@employee, old_code: old_code)
      end

      redirect_to admin_employees_path, notice: "#{@employee.name} updated."
    rescue ActiveRecord::RecordInvalid => error
      form_employee = employee_form_after_error(error, @employee)
      load_employee_context(form_employee: form_employee)
      flash.now[:alert] = form_employee.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    def toggle_active
      @employee.update!(active: !@employee.active?)
      sync_employee_login!(@employee) if @employee.active?

      redirect_to admin_employees_path,
        notice: "#{@employee.name} #{@employee.active? ? "enabled" : "disabled"}."
    end

    private

    def load_employee_context(form_employee: nil)
      active_bli_activity_sql = ActiveRecord::Base.connection.quote(true)

      @employees = Employee
        .includes(:user)
        .left_joins(:bli_activities)
        .select("employees.*, COUNT(CASE WHEN bli_activities.import_flag = 0 AND bli_activities.active = #{active_bli_activity_sql} THEN 1 END) AS activities_count")
        .group("employees.id")
        .order(:name)

      @summary = {
        employees: Employee.count,
        active_employees: Employee.where(active: true).count,
        activities: BliActivity.active.count,
        verticals: BliActivity.active.distinct.count(:vertical_name),
        projects: BliActivity.active.distinct.count(:project_name),
        utilised: BliActivity.active.sum(:utilised_fund)
      }

      @summary[:inactive_employees] = @summary[:employees] - @summary[:active_employees]
      @employee_form = form_employee || Employee.find_by(id: params[:edit_id]) || Employee.new(active: true)
    end

    def set_employee
      @employee = Employee.find(params[:id])
    end

    def employee_params
      params.require(:employee).permit(
        :employee_code,
        :name,
        :email,
        :mobile_number,
        :designation,
        :functional_responsibility,
        :department,
        :branch,
        :sub_branch,
        :office_name,
        :primary_vertical,
        :primary_project,
        :active
      ).tap do |attributes|
        attributes[:employee_code] = normalize_employee_code(attributes[:employee_code])
        attributes[:active] = ActiveModel::Type::Boolean.new.cast(attributes[:active])
      end
    end

    def normalize_employee_code(value)
      ProjectOwnership.normalize_employee_code(value)
    end

    def sync_employee_code_references!(old_code, employee)
      timestamp = Time.current
      ActionPlanFcoMapping.where(employee_id: employee.id).update_all(employee_code: employee.employee_code, updated_at: timestamp)
      ActionPlanVerticalMapping.where(employee_id: employee.id).update_all(employee_code: employee.employee_code, updated_at: timestamp)
      ProjectOwnership.where(project_owner_id: old_code).update_all(project_owner_id: employee.employee_code, updated_at: timestamp)
    end

    def sync_employee_login!(employee, old_code: nil)
      user = employee.user || User.find_by(login: old_code) || User.find_or_initialize_by(login: employee.employee_code)

      if user.persisted? && user.employee_id.present? && user.employee_id != employee.id
        employee.errors.add(:employee_code, "already has another login")
        raise ActiveRecord::RecordInvalid, employee
      end

      user.login = employee.employee_code
      user.employee = employee
      user.password = employee.employee_code.downcase if user.new_record?
      user.save!
    rescue ActiveRecord::RecordInvalid => error
      employee.errors.add(:base, error.record.errors.full_messages.to_sentence)
      raise ActiveRecord::RecordInvalid, employee
    end

    def employee_form_after_error(error, fallback)
      return error.record if error.record.is_a?(Employee)

      fallback.tap do |employee|
        employee.errors.add(:base, error.record.errors.full_messages.to_sentence)
      end
    end
  end
end

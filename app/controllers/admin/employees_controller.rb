module Admin
  class EmployeesController < ApplicationController
    before_action :require_login
    before_action :require_admin

    def index
      @employees = Employee
        .includes(:user)
        .left_joins(:bli_activities)
        .select("employees.*, COUNT(bli_activities.id) AS activities_count")
        .group("employees.id")
        .order(:name)

      @summary = {
        employees: Employee.count,
        active_employees: Employee.where(active: true).count,
        activities: BliActivity.count,
        verticals: BliActivity.distinct.count(:vertical_name),
        projects: BliActivity.distinct.count(:project_name),
        utilised: BliActivity.sum(:utilised_fund)
      }
    end
  end
end

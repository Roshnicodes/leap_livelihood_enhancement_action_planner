class PhnDashboardsController < ApplicationController
  before_action :require_login
  before_action :require_admin

  def show
    @dashboard_link = DashboardLink.pnb_dashboard
  end

  def settings
    @dashboard_link = DashboardLink.pnb_dashboard
  end

  def update
    @dashboard_link = DashboardLink.pnb_dashboard
    @dashboard_link.assign_attributes(dashboard_link_params.merge(updated_by: current_user))

    if @dashboard_link.save
      redirect_to settings_pnb_dashboard_path, notice: "PNB Dashboard link updated."
    else
      render :settings, status: :unprocessable_entity
    end
  end

  private

  def dashboard_link_params
    params.require(:dashboard_link).permit(:url)
  end
end

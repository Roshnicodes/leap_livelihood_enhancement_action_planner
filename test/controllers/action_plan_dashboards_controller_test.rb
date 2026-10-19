require "test_helper"

class ActionPlanDashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "ap-dashboard-mis", role: "admin", password: "secret")
    @employee = Employee.create!(employee_code: "AP-DASH-1", name: "Dashboard Viewer", active: true)
    @user = User.create!(login: @employee.employee_code, employee: @employee, password: "secret")
  end

  test "MIS sets the Action Plan dashboard link and then sees it from the MIS menu" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get action_plan_dashboard_path
    assert_response :success
    assert_select "h1", "Action Plan Dashboard"
    assert_select "iframe", count: 0
    assert_select "a[href='#{settings_action_plan_dashboard_path}']", text: "Add Dashboard Link"
    assert_select ".sidebar-section.is-open a[href='#{action_plan_dashboard_path}']", text: /Action Plan Dashboard/
    assert_select ".sidebar-section.is-open a[href='#{settings_action_plan_dashboard_path}']", text: /Action Plan Link Settings/

    url = "https://app.powerbi.com/view?r=action-plan"
    patch settings_action_plan_dashboard_path, params: { dashboard_link: { url: url } }
    assert_redirected_to settings_action_plan_dashboard_path
    assert_equal @admin, DashboardLink.action_plan_dashboard.updated_by

    get action_plan_dashboard_path
    assert_select "iframe[title='Action Plan Dashboard'][src='#{url}']"
    assert_equal DashboardLink::DEFAULT_PNB_DASHBOARD_URL, DashboardLink.pnb_dashboard.url
  end

  test "an invalid link is not saved" do
    post login_path, params: { login: @admin.login, password: "secret" }

    patch settings_action_plan_dashboard_path, params: { dashboard_link: { url: "not a url" } }

    assert_response :unprocessable_entity
    assert_not DashboardLink.action_plan_dashboard.persisted?
  end

  test "non MIS users cannot open the dashboard or its settings" do
    post login_path, params: { login: @user.login, password: "secret" }

    get action_plan_dashboard_path
    assert_redirected_to dashboard_path

    patch settings_action_plan_dashboard_path, params: { dashboard_link: { url: "https://example.com" } }
    assert_redirected_to dashboard_path
    assert_not DashboardLink.action_plan_dashboard.persisted?
  end
end

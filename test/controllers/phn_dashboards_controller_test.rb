require "test_helper"

class PhnDashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "phn-mis", role: "admin", password: "secret")
    @employee = Employee.create!(employee_code: "PHN-1", name: "PHN Viewer", active: true)
    @user = User.create!(login: @employee.employee_code, employee: @employee, password: "secret")
  end

  test "MIS can open the PNB dashboard from the MIS menu" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get pnb_dashboard_path

    assert_response :success
    assert_select "h1", "PNB Dashboard"
    assert_select ".sidebar-section.is-open a[href='#{pnb_dashboard_path}']", text: /PNB Dashboard/
    assert_select ".sidebar-section.is-open a[href='#{settings_pnb_dashboard_path}']", text: /PNB Link Settings/
    assert_select "iframe[title='PNB Dashboard'][src='#{DashboardLink::DEFAULT_PNB_DASHBOARD_URL}']"
    assert_select "input[name='dashboard_link[url]']", count: 0
    assert_select "a", text: "Open in new tab", count: 0
  end

  test "MIS can update the PNB dashboard URL from its separate settings page" do
    post login_path, params: { login: @admin.login, password: "secret" }
    updated_url = "https://app.powerbi.com/view?r=updated-dashboard"

    get settings_pnb_dashboard_path

    assert_response :success
    assert_select "h1", "PNB Dashboard Settings"
    assert_select "input[name='dashboard_link[url]'][value='#{DashboardLink::DEFAULT_PNB_DASHBOARD_URL}']"

    patch settings_pnb_dashboard_path, params: { dashboard_link: { url: updated_url } }

    assert_redirected_to settings_pnb_dashboard_path
    dashboard_link = DashboardLink.pnb_dashboard
    assert_equal updated_url, dashboard_link.url
    assert_equal @admin, dashboard_link.updated_by
  end

  test "non MIS users cannot open the dashboard or its link settings" do
    post login_path, params: { login: @user.login, password: "secret" }

    get pnb_dashboard_path

    assert_redirected_to dashboard_path

    get settings_pnb_dashboard_path

    assert_redirected_to dashboard_path

    patch settings_pnb_dashboard_path, params: { dashboard_link: { url: "https://example.com" } }

    assert_redirected_to dashboard_path
  end
end

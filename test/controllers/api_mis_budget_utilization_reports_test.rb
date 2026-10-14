require "test_helper"

class ApiMisBudgetUtilizationReportsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-api-admin", role: "admin", password: "secret")
    @employee = Employee.create!(employee_code: "MIS-API-1", name: "MIS User", active: true)
    VerticalPercent.create!(vertical_name: "MIS Vertical", total: 100, apr: 100)
    BliActivity.create!(
      employee: @employee, project_name: "MIS Project", vertical_name: "MIS Vertical",
      activity_name: "MIS Activity", responsible_user_name: "MIS User", bli_code: "BLI-MIS",
      name: "MIS BLI", allocated_fund: 1000, remaining_fund: 1000, active: true, import_flag: 0
    )
    BudgetUtilization.create!(
      project_name: "MIS Project", vertical_name: "MIS Vertical", activity_name: "MIS Activity",
      bli_code: "BLI-MIS", month: "apr", planned_amount: 1000, utilized_amount: 250, status: "submitted"
    )
  end

  test "returns the MIS budget utilization report as JSON for admins" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get api_mis_budget_utilization_path, params: { project: "MIS Project", period: "monthly", period_month: "apr" }

    assert_response :success
    body = response.parsed_body
    assert_equal [ "apr" ], body["months"]
    row = body["rows"].sole
    assert_equal "BLI-MIS", row["bli_code"]
    assert_equal 250.0, row["total_expenditure"]
    assert_equal({ "month" => "apr", "allocated" => 1000.0, "expenses" => 250.0 }, row["months"].sole)
    assert_equal 750.0, body["summary"]["remaining_total"]
  end

  test "report tools can read the API live with the API key" do
    with_api_key("k" * 40) do
      get api_mis_budget_utilization_path, params: { api_key: "k" * 40, project: "MIS Project", period: "monthly", period_month: "apr" }
      assert_response :success
      assert_equal 250.0, response.parsed_body["rows"].sole["total_expenditure"]

      get api_project_action_plan_path, headers: { "X-Api-Key" => "k" * 40 }
      assert_response :success

      get api_mis_budget_utilization_path, params: { api_key: "wrong" }
      assert_response :unauthorized
      assert_equal "Invalid API key.", response.parsed_body["error"]
    end
  end

  test "API key does nothing until a long enough key is configured" do
    with_api_key(nil) do
      get api_mis_budget_utilization_path, params: { api_key: "anything" }
      assert_response :unauthorized
    end

    with_api_key("short") do
      get api_mis_budget_utilization_path, params: { api_key: "short" }
      assert_response :unauthorized
    end
  end

  test "asks for login as JSON instead of redirecting" do
    get api_mis_budget_utilization_path

    assert_response :unauthorized
    assert_equal "Please login to continue.", response.parsed_body["error"]
  end

  private

  def with_api_key(key)
    previous = ENV["LEAP_API_KEY"]
    ENV["LEAP_API_KEY"] = key
    yield
  ensure
    ENV["LEAP_API_KEY"] = previous
  end
end

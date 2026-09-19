require "test_helper"
require "zip"

class ActionPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(login: "mis-action-plan", role: "admin", password: "secret")
    post login_path, params: { login: @admin.login, password: "secret" }

    create_action_plan_row(statte: "CG", apr: 4, apr_t: 1)
    create_action_plan_row(statte: "MP", apr: 6, apr_t: 2)
  end

  test "without state hides state column and groups matching rows" do
    get action_plans_path(project: "all", state: ActionPlanRow::WITHOUT_STATE_FILTER_VALUE)

    assert_response :success
    assert_select "option[value='#{ActionPlanRow::WITHOUT_STATE_FILTER_VALUE}']", text: "Without State"
    assert_select ".action-plan-table th", text: "State", count: 0
    assert_select "[data-filtered-count]", text: "1 activities"
  end

  test "without state download omits state column" do
    get download_action_plans_path(project: "all", state: ActionPlanRow::WITHOUT_STATE_FILTER_VALUE)

    assert_response :success
    assert_equal XlsxWorkbook::CONTENT_TYPE, response.media_type

    sheet_xml = xlsx_sheet_xml(response.body)
    assert_no_match(%r{<t>State</t>}, sheet_xml)
    assert_includes sheet_xml, "Project_Owner"
  end

  private

  def create_action_plan_row(attributes)
    ActionPlanRow.create!(
      {
        po_id: "PO-1",
        project_id: "21",
        project_name: "Ashraya Hastha Trust",
        project_owner: "Owner",
        user_id: "9",
        user_name: "Ambikapur - FCO",
        to_id: "89",
        to_name: "Sitapur - TO",
        asa_theme_id: "1",
        asa_theme: "Programme Coverage",
        asa_activity_id: "1.2",
        asa_activity_name: "Coverage",
        theme_id: "T1",
        theme: "Project Theme",
        activity_id: "3.1",
        activity: "Project Activity",
        unit_type: "Count",
        planned_total: attributes[:apr].to_i,
        original_apr: attributes[:apr].to_i
      }.merge(attributes)
    )
  end

  def xlsx_sheet_xml(body)
    Zip::File.open_buffer(StringIO.new(body)) do |zip|
      return zip.read("xl/worksheets/sheet1.xml")
    end
  end
end

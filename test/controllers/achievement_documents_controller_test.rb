require "test_helper"

class AchievementDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fco = Employee.create!(employee_code: "DOC-FCO", name: "Docs FCO", active: true)
    User.create!(login: @fco.employee_code, employee: @fco, password: "secret")
    ActionPlanFcoMapping.create!(employee: @fco, employee_code: @fco.employee_code, fco_id: "DOC1", fco_name: "Docs FCO")
    @admin = User.create!(login: "docs-mis", role: "admin", password: "secret")

    @own_row = create_row("DOC1", "Docs FCO", "1.1", "Goat support")
    @other_row = create_row("DOC2", "Other FCO", "1.2", "Seed support")

    attach(@own_row, "apr", "april-proof.pdf")
    attach(@own_row, "may", "may-photo.jpg", content_type: "image/jpeg")
    attach(@other_row, "apr", "other-fco.pdf")
    AchievementEntryDetail.create!(action_plan_row: @own_row, month: "jun", remark: "No file")
  end

  test "FCO sees only its own documents, grouped by month in financial-year order" do
    post login_path, params: { login: @fco.employee_code, password: "secret" }

    get achievement_documents_path

    assert_response :success
    assert_equal %w[Apr May], css_select("section.table-panel h2").map { |node| node.text.strip }
    assert_includes response.body, "april-proof.pdf"
    assert_includes response.body, "may-photo.jpg"
    assert_not_includes response.body, "other-fco.pdf"
    assert_select ".sidebar-section.is-open a[href='#{achievement_documents_path}']", text: /Achievement Documents/
  end

  test "files uploaded before a re-import still show" do
    @own_row.update!(import_flag: 1)
    post login_path, params: { login: @fco.employee_code, password: "secret" }

    get achievement_documents_path

    assert_includes response.body, "april-proof.pdf"
    assert_not_includes response.body, "other-fco.pdf"
  end

    test "month filter narrows the list and MIS sees every FCO" do
    post login_path, params: { login: @admin.login, password: "secret" }

    get achievement_documents_path, params: { month: "apr" }

    assert_response :success
    assert_equal %w[Apr], css_select("section.table-panel h2").map { |node| node.text.strip }
    assert_includes response.body, "april-proof.pdf"
    assert_includes response.body, "other-fco.pdf"
    assert_not_includes response.body, "may-photo.jpg"
  end

  test "users without achievement record access are sent away" do
    employee = Employee.create!(employee_code: "DOC-NONE", name: "No Access", active: true)
    User.create!(login: employee.employee_code, employee: employee, password: "secret")
    post login_path, params: { login: employee.employee_code, password: "secret" }

    get achievement_documents_path

    assert_redirected_to dashboard_path
  end

  private

  def create_row(user_id, user_name, activity_id, activity_name)
    ActionPlanRow.create!(
      po_id: "PO-DOC", project_name: "Docs Project", user_id: user_id, user_name: user_name,
      to_id: "TO-#{user_id}", to_name: "TO #{user_name}", statte: "MP", asa_theme_id: "1", asa_theme: "Livelihood",
      asa_activity_id: activity_id, asa_activity_name: activity_name, activity: activity_name, unit_type: "Nos",
      apr: 1, may: 1, planned_total: 2, import_flag: 0, active: true
    )
  end

  def attach(row, month, filename, content_type: "application/pdf")
    detail = AchievementEntryDetail.find_or_initialize_by(action_plan_row: row, month: month)
    detail.files.attach(io: StringIO.new("file"), filename: filename, content_type: content_type)
    detail.save!
  end
end

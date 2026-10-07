require "test_helper"

class XlsxWorkbookTest < ActiveSupport::TestCase
  test "uses the Excel-compatible legacy hash for sheet protection passwords" do
    workbook = XlsxWorkbook.new([])

    assert_equal "83AF", workbook.send(:excel_password_hash, "password")
  end
end

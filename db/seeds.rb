require "csv"
require "rexml/document"
require "zip"

employee_xlsx_path = ENV.fetch("EMPLOYEE_XLSX_PATH", "/home/asa/Downloads/roshini emp.xlsx")
employee_csv_path = ENV.fetch("EMPLOYEE_CSV_PATH", "/tmp/roshini emp.csv")
vertical_percent_xlsx_path = ENV.fetch("VERTICAL_PERCENT_XLSX_PATH", "/home/asa/Downloads/ASA Theme User (1).xlsx")
active_employee_codes = %w[937 397 237 939 840 644 1079 1666 1025 1155 1621 1495 1686 1431 1759].freeze

def money(value)
  BigDecimal(value.to_s.presence || "0")
rescue ArgumentError
  0
end

def normalize_name(value)
  value.to_s.squish.downcase
end

def xlsx_employee_rows(path)
  Zip::File.open(path) do |zip|
    shared_strings = xlsx_shared_strings(zip)
    rows = []

    zip.glob("xl/worksheets/sheet*.xml").sort_by(&:name).each do |entry|
      rows.concat(xlsx_sheet_rows(zip.read(entry.name), shared_strings))
    end

    rows
  end
end

def xlsx_sheet_rows(sheet_xml, shared_strings)
  document = REXML::Document.new(sheet_xml)
  namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
  rows = []

  REXML::XPath.each(document, "//xmlns:sheetData/xmlns:row", namespaces) do |row|
    values = []

    REXML::XPath.each(row, "xmlns:c", namespaces) do |cell|
      column_index = cell.attribute("r").to_s[/[A-Z]+/].chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
      values[column_index] = xlsx_cell_value(cell, shared_strings)
    end

    rows << values
  end

  headers = unique_headers(rows.shift.to_a.map { |header| header.to_s.squish })
  return [] unless headers.include?("Employee Code")

  rows.map { |values| headers.zip(values).to_h }
end

def unique_headers(headers)
  counts = Hash.new(0)

  headers.map do |header|
    counts[header] += 1
    counts[header] == 1 ? header : "#{header} #{counts[header]}"
  end
end

def xlsx_shared_strings(zip)
  return [] unless zip.find_entry("xl/sharedStrings.xml")

  document = REXML::Document.new(zip.read("xl/sharedStrings.xml"))
  namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
  strings = []
  REXML::XPath.each(document, "//xmlns:si", namespaces) do |item|
    strings << REXML::XPath.match(item, ".//xmlns:t", namespaces).map(&:text).join
  end
  strings
end

def xlsx_cell_value(cell, shared_strings)
  type = cell.attribute("t").to_s
  namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
  value = REXML::XPath.first(cell, "xmlns:v", namespaces)&.text
  return shared_strings[value.to_i].to_s if type == "s"
  return REXML::XPath.match(cell, ".//xmlns:t", namespaces).map(&:text).join if type == "inlineStr"

  value.to_s
end

def employee_rows(csv_path, xlsx_path)
  return xlsx_employee_rows(xlsx_path) if File.exist?(xlsx_path)

  return CSV.read(csv_path, headers: true, encoding: "bom|utf-8").map(&:to_h) if File.exist?(csv_path)

  []
end

def vertical_percent_rows(xlsx_path)
  return [] unless File.exist?(xlsx_path)

  Zip::File.open(xlsx_path) do |zip|
    shared_strings = xlsx_shared_strings(zip)
    rows = []

    zip.glob("xl/worksheets/sheet*.xml").sort_by(&:name).each do |entry|
      sheet_rows = xlsx_generic_sheet_rows(zip.read(entry.name), shared_strings)
      rows.concat(sheet_rows) if sheet_rows.any? { |row| row.key?("Parent Activity") || row.key?("Vertical") }
    end

    rows
  end
end

def xlsx_generic_sheet_rows(sheet_xml, shared_strings)
  document = REXML::Document.new(sheet_xml)
  namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
  rows = []

  REXML::XPath.each(document, "//xmlns:sheetData/xmlns:row", namespaces) do |row|
    values = []

    REXML::XPath.each(row, "xmlns:c", namespaces) do |cell|
      column_index = cell.attribute("r").to_s[/[A-Z]+/].chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
      values[column_index] = xlsx_cell_value(cell, shared_strings)
    end

    rows << values
  end

  headers = unique_headers(rows.shift.to_a.map { |header| header.to_s.squish })
  rows.map { |values| headers.zip(values).to_h }
end

def row_value(row, *headers)
  normalized = row.transform_keys { |key| key.to_s.squish.downcase }
  headers.each do |header|
    value = normalized[header.to_s.squish.downcase].to_s.squish
    return value if value.present?
  end

  nil
end

ActiveRecord::Base.transaction do
  PlanSubmissionItem.delete_all
  PlanSubmission.delete_all
  ProjectSummarySubmissionItem.delete_all
  ProjectSummarySubmission.delete_all
  EmployeeVerticalMapping.delete_all
  VerticalPercent.delete_all
  BliActivity.delete_all
  User.delete_all
  Employee.delete_all

  admin = User.new(login: "admin@leap.local", role: "admin")
  admin.password = "admin123"
  admin.save!

  vertical_percent_rows(vertical_percent_xlsx_path).each do |row|
    VerticalPercent.create!(
      vertical_name: row_value(row, "Vertical", "Parent Activity"),
      total: money(row_value(row, "Total")),
      apr: money(row_value(row, "Apr")),
      may: money(row_value(row, "May")),
      jun: money(row_value(row, "Jun")),
      jul: money(row_value(row, "Jul")),
      aug: money(row_value(row, "Aug")),
      sep: money(row_value(row, "Sep")),
      oct: money(row_value(row, "Oct")),
      nov: money(row_value(row, "Nov")),
      dec: money(row_value(row, "Dec")),
      jan: money(row_value(row, "Jan")),
      feb: money(row_value(row, "Feb")),
      mar: money(row_value(row, "Mar"))
    )
  end

  employee_by_name = {}
  employee_sequence = 0

  employee_rows(employee_csv_path, employee_xlsx_path)
    .index_by { |row| row["Employee Code"].to_s.squish }
    .except("")
    .each_value do |row|
      employee = Employee.create!(
        employee_code: row_value(row, "Employee Code"),
        name: row_value(row, "Name", "Employee Name"),
        active: active_employee_codes.include?(row_value(row, "Employee Code")),
        email: row_value(row, "Email", "Work email"),
        mobile_number: row_value(row, "Mobile Number", "Mobile number", "Mobile No"),
        department: row_value(row, "Department", "Dept"),
        primary_vertical: row_value(row, "Department", "Dept"),
        designation: row_value(row, "Designation"),
        functional_responsibility: row_value(row, "Functional Responsibility"),
        branch: row_value(row, "Branch"),
        sub_branch: row_value(row, "Sub branch")
      )

      employee_by_name[normalize_name(employee.name)] = employee
      employee_sequence += 1
  end

  Employee.find_each do |employee|
    user = User.new(login: employee.employee_code, role: "user", employee: employee)
    user.password = employee.employee_code.downcase
    user.save!
  end

  jayanthi = Employee.find_or_initialize_by(employee_code: "002")
  jayanthi.assign_attributes(
    name: "Jayanthi Gangana",
    active: true,
    email: "jayanthi@asabhopal.org",
    mobile_number: "9425010782",
    designation: "Director"
  )
  jayanthi.save!

  user = User.find_or_initialize_by(login: jayanthi.employee_code)
  user.employee = jayanthi
  user.role = "user"
  user.password = jayanthi.employee_code.downcase if user.new_record?
  user.save!

  if Employee.none?
    employee = Employee.create!(
      employee_code: "EMP0001",
      name: "Demo User",
      active: true,
      email: "demo.user@example.com",
      mobile_number: "9999999999",
      department: "LWRD",
      office_name: "HO-Bhopal",
      primary_vertical: "WRD",
      primary_project: "Demo Project"
    )

    user = User.new(login: employee.employee_code, role: "user", employee: employee)
    user.password = employee.employee_code.downcase
    user.save!
  end
end

puts "Seeded #{Employee.count} employees, #{User.count} users, #{BliActivity.count} BLI activities."

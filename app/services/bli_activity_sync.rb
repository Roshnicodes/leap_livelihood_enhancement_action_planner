require "csv"
require "rexml/document"
require "zip"

class BliActivitySync
  DEFAULT_CSV_PATH = "/home/asa/Downloads/bli_list (3).csv"
  DEFAULT_XLSX_PATH = "/home/asa/Downloads/ASA BLI PDO.xlsx"
  DEFAULT_FINANCIAL_YEAR = "2026-2027"

  def initialize(csv_path: DEFAULT_CSV_PATH, xlsx_path: DEFAULT_XLSX_PATH, financial_year: DEFAULT_FINANCIAL_YEAR)
    @csv_path = csv_path
    @xlsx_path = xlsx_path
    @financial_year = financial_year
  end

  def call(clear_summaries: false)
    ActiveRecord::Base.transaction do
      clear_existing_records(clear_summaries)

      source_rows.each do |row|
        next unless row_value(row, "Financial Year") == financial_year

        row_vertical = row_value(row, "Parent Activity", "Vertical")
        employees_mapped_to_vertical(row_vertical).find_each do |employee|
          create_activity(employee, row, row_vertical)
        end
      end
    end

    BliActivity.count
  end

  private

  attr_reader :csv_path, :xlsx_path, :financial_year

  def clear_existing_records(clear_summaries)
    PlanSubmissionItem.delete_all
    PlanSubmission.delete_all

    if clear_summaries
      ProjectSummarySubmissionItem.delete_all
      ProjectSummarySubmission.delete_all
    end

    BliActivity.delete_all
  end

  def source_rows
    return CSV.read(csv_path, headers: true, encoding: "bom|utf-8").map(&:to_h) if File.exist?(csv_path)
    return xlsx_bli_rows(xlsx_path) if File.exist?(xlsx_path)

    []
  end

  def employees_mapped_to_vertical(vertical_name)
    Employee
      .joins(employee_vertical_mappings: :vertical_percent)
      .where("LOWER(TRIM(vertical_percents.vertical_name)) = ?", vertical_name.to_s.squish.downcase)
      .distinct
  end

  def create_activity(employee, row, row_vertical)
    allocated_fund = money(row_value(row, "BLI Allocated Fund", "Project BLI Allocated Fund"))
    remaining_fund = row_value(row, "BLI Remaining Fund").present? ? money(row_value(row, "BLI Remaining Fund")) : allocated_fund

    BliActivity.create!(
      employee: employee,
      stakeholder_name: row_value(row, "Stakeholder Name"),
      allocating_date: parsed_date(row_value(row, "Allocating Date")),
      name: row_value(row, "Name", "Project Name"),
      bli_code: clean_code(row_value(row, "BLI Code", "Project BLI Code")),
      allocated_fund: allocated_fund,
      remaining_fund: remaining_fund,
      financial_year: row_value(row, "Financial Year"),
      project_name: project_label(row),
      office_name: row_value(row, "Office Name"),
      vertical_name: row_vertical,
      parent_activity: row_vertical,
      activity_name: activity_label(row),
      responsible_user_name: employee.name,
      utilised_fund: money(row_value(row, "Utilised Fund")),
      approved_utilised_fund: money(row_value(row, "Utilised (Approved) Fund")),
      total_pdo_count: count(row_value(row, "Total PDO Count")),
      total_pdo_amount: money(row_value(row, "Total PDO Amount")),
      approved_pdo_count: count(row_value(row, "Approved PDO Count")),
      approved_pdo_amount: money(row_value(row, "Approved PDO Amount")),
      pending_pdo_count: count(row_value(row, "Pending PDO Count")),
      pending_pdo_amount: money(row_value(row, "Pending PDO Amount")),
      total_rfp_count: count(row_value(row, "Total RFP Count")),
      total_rfp_amount: money(row_value(row, "Total RFP Amount")),
      approved_rfp_count: count(row_value(row, "Approved RFP Count")),
      approved_rfp_amount: money(row_value(row, "Approved RFP Amount")),
      pending_rfp_count: count(row_value(row, "Pending RFP Count")),
      pending_rfp_amount: money(row_value(row, "Pending RFP Amount"))
    )
  end

  def xlsx_bli_rows(path)
    return [] unless File.exist?(path)

    Zip::File.open(path) do |zip|
      shared_strings = xlsx_shared_strings(zip)
      rows = []

      zip.glob("xl/worksheets/sheet*.xml").sort_by(&:name).each do |entry|
        sheet_rows = xlsx_generic_sheet_rows(zip.read(entry.name), shared_strings)
        rows.concat(sheet_rows) if sheet_rows.any? { |row| row.key?("Responsible Users") }
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

  def unique_headers(headers)
    counts = Hash.new(0)

    headers.map do |header|
      counts[header] += 1
      counts[header] == 1 ? header : "#{header} #{counts[header]}"
    end
  end

  def row_value(row, *headers)
    normalized = row.transform_keys { |key| key.to_s.squish.downcase }
    headers.each do |header|
      value = normalized[header.to_s.squish.downcase].to_s.squish
      return value if value.present?
    end

    nil
  end

  def activity_label(row)
    row_value(row, "Activity", "ASA Activity", "Name", "Project Name", "BLI Code", "Project BLI Code") || "Untitled activity"
  end

  def project_label(row)
    project_name = row_value(row, "Project Name 2", "Project Name")
    return "Corteva (Existing & (New FPO)" if project_name.to_s.squish.casecmp("Corteva").zero?

    project_name
  end

  def money(value)
    BigDecimal(value.to_s.gsub(/[^0-9.-]/, "").presence || "0")
  rescue ArgumentError
    0
  end

  def count(value)
    value.to_i
  end

  def parsed_date(value)
    Date.strptime(value.to_s, "%d-%m-%Y")
  rescue Date::Error
    nil
  end

  def clean_code(value)
    code = value.to_s.squish
    return code unless code.match?(/\A-?\d+(\.\d+)?\z/)

    BigDecimal(code).round(4).to_s("F").sub(/\.?0+\z/, "")
  rescue ArgumentError
    code
  end
end

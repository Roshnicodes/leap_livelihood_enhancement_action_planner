require "csv"
require "rexml/document"
require "zlib"
require "zip"

class BliActivitySync
  DEFAULT_CSV_PATH = "/home/asa/Downloads/bli-roshni.csv"
  DEFAULT_XLSX_PATH = "/home/asa/Downloads/ASA BLI PDO.xlsx"
  DEFAULT_FINANCIAL_YEAR = "2026-2027"

  def initialize(csv_path: DEFAULT_CSV_PATH, xlsx_path: DEFAULT_XLSX_PATH, source_path: nil, financial_year: DEFAULT_FINANCIAL_YEAR, save_history: true)
    @csv_path = csv_path
    @xlsx_path = xlsx_path
    @source_path = source_path
    @financial_year = financial_year
    @save_history = save_history
  end

  def call(clear_summaries: false)
    source_file = effective_source_path
    PbImportFile.capture_active_snapshot! if save_history && source_file.present?

    ActiveRecord::Base.transaction do
      clear_existing_records(clear_summaries)

      source_rows.each do |row|
        next unless row_value(row, "Financial Year") == financial_year

        source_parent_activity = row_value(row, "Parent Activity", "Vertical")
        assignments = assignments_for_parent_activity(source_parent_activity)

        if assignments.exists?
          assignments.includes(:employee, :vertical_percent).find_each do |assignment|
            create_activity(assignment.employee, row, assignment.vertical_percent.vertical_name)
          end
        elsif (employee = employee_for_responsible_user(row))
          create_activity(employee, row, vertical_name_for_parent_activity(source_parent_activity))
        else
          mapped_employees = employees_mapped_to_vertical(source_parent_activity).to_a
          mapped_employees = [ placeholder_employee_for_responsible_user(row) ].compact if mapped_employees.blank?

          mapped_employees.each do |employee|
            create_activity(employee, row, source_parent_activity)
          end
        end
      end
    end

    imported_count = BliActivity.count
    if save_history && source_file.present?
      PbImportFile.capture_path!(
        path: source_file,
        original_filename: File.basename(source_file),
        status: "imported",
        file_kind: "source",
        row_count: imported_count
      )
    end

    imported_count
  end

  private

  attr_reader :csv_path, :xlsx_path, :source_path, :financial_year, :save_history

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
    if effective_source_path.present?
      return CSV.read(effective_source_path, headers: true, encoding: "bom|utf-8").map(&:to_h) if File.extname(effective_source_path).downcase == ".csv"
      return xlsx_bli_rows(effective_source_path)
    end

    return CSV.read(csv_path, headers: true, encoding: "bom|utf-8").map(&:to_h) if File.exist?(csv_path)
    return xlsx_bli_rows(xlsx_path) if File.exist?(xlsx_path)

    []
  end

  def effective_source_path
    @effective_source_path ||= begin
      explicit_path = source_path.to_s
      if explicit_path.present? && File.exist?(explicit_path)
        explicit_path
      elsif File.exist?(csv_path)
        csv_path
      elsif File.exist?(xlsx_path)
        xlsx_path
      end
    end
  end

  def employees_mapped_to_vertical(vertical_name)
    Employee
      .joins(employee_vertical_mappings: :vertical_percent)
      .where("LOWER(TRIM(vertical_percents.vertical_name)) = ?", vertical_name.to_s.squish.downcase)
      .distinct
  end

  def assignments_for_parent_activity(source_parent_activity)
    ParentActivityAssignment.where(
      "LOWER(TRIM(source_parent_activity)) = ?",
      source_parent_activity.to_s.squish.downcase
    )
  end

  def employee_for_responsible_user(row)
    responsible_user_name = row_value(row, "Responsible Users", "Responsible User")
    return if responsible_user_name.blank?

    normalized_name = responsible_user_name.to_s.squish.downcase
    exact_match = Employee.find_by("LOWER(TRIM(name)) = ?", normalized_name)
    return exact_match if exact_match

    tokens = normalized_name.split(/\s+/)
    return if tokens.blank?

    Employee.where(tokens.map { "LOWER(name) LIKE ?" }.join(" AND "), *tokens.map { |token| "%#{token}%" }).first
  end

  def placeholder_employee_for_responsible_user(row)
    responsible_user_name = row_value(row, "Responsible Users", "Responsible User")
    return if responsible_user_name.blank?

    normalized_name = responsible_user_name.to_s.squish
    Employee.find_or_create_by!(employee_code: placeholder_employee_code(normalized_name)) do |employee|
      employee.name = normalized_name
      employee.active = false
      employee.primary_project = project_label(row)
      employee.primary_vertical = row_value(row, "Parent Activity", "Vertical")
      employee.office_name = row_value(row, "Office Name")
    end
  end

  def placeholder_employee_code(name)
    "AUTO-#{Zlib.crc32(name.to_s.downcase).to_s(36).upcase}"
  end

  def vertical_name_for_parent_activity(source_parent_activity)
    source_name = source_parent_activity.to_s.squish
    return "Com. Trng. Tools & Materials - General" if source_name.start_with?("Com. Trng. Tools & Materials - General")

    VerticalPercent.find_by("LOWER(TRIM(vertical_name)) = ?", source_name.downcase)&.vertical_name || source_name
  end

  def create_activity(employee, row, row_vertical)
    allocated_fund = money(row_value(row, "BLI Allocated Fund", "Project BLI Allocated Fund"))
    remaining_fund = row_value(row, "BLI Remaining Fund").present? ? money(row_value(row, "BLI Remaining Fund")) : allocated_fund

    BliActivity.create!(
      employee: employee,
      stakeholder_name: row_value(row, "Stakeholder Name"),
      allocating_date: parsed_date(row_value(row, "Allocating Date")),
      name: row_value(row, "Project Bli Name", "Name", "Project Name"),
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

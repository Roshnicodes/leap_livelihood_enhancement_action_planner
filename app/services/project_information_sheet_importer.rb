require "csv"
require "rexml/document"
require "zip"

class ProjectInformationSheetImporter
  HEADER_MAP = {
    "project id" => :project_id,
    "project title" => :project_title,
    "donor" => :donor,
    "category" => :category,
    "project period" => :project_period,
    "total" => :total,
    "project location" => :project_location,
    "project area map" => :project_area_map,
    "donor reporting officer" => :donor_reporting_officer,
    "start date" => :start_date,
    "end date" => :end_date,
    "project objectives" => :project_objectives,
    "no of hh to be covered" => :households_to_be_covered,
    "fco name" => :fco_name,
    "po" => :po,
    "reporting system" => :reporting_system,
    "physical" => :physical,
    "financial" => :financial,
    "annexure" => :annexure
  }.freeze

  Result = Data.define(:created, :updated, :skipped)

  def initialize(file:, uploaded_by:)
    @file = file
    @uploaded_by = uploaded_by
  end

  def import!
    created = 0
    updated = 0
    skipped = 0

    ActiveRecord::Base.transaction do
      rows.each do |row|
        attributes = attributes_for(row)
        if attributes[:project_id].blank?
          skipped += 1
          next
        end

        record = ProjectInformationSheet.find_or_initialize_by(project_id: attributes[:project_id])
        record.assign_attributes(attributes.merge(uploaded_by: uploaded_by))
        record.new_record? ? created += 1 : updated += 1
        record.save!
      end
    end

    Result.new(created:, updated:, skipped:)
  end

  private

  attr_reader :file, :uploaded_by

  def rows
    extension = File.extname(file.original_filename.to_s).downcase
    case extension
    when ".csv"
      csv_rows
    when ".xlsx"
      xlsx_rows
    else
      raise ArgumentError, "Only CSV and XLSX files are supported."
    end
  end

  def csv_rows
    raw_rows = CSV.read(file.path, encoding: "bom|utf-8")
    rows_from_raw(raw_rows)
  end

  def xlsx_rows
    Zip::File.open(file.path) do |zip|
      shared_strings = xlsx_shared_strings(zip)
      sheet_entry = zip.glob("xl/worksheets/sheet*.xml").sort_by(&:name).first
      return [] unless sheet_entry

      xlsx_sheet_rows(zip.read(sheet_entry.name), shared_strings)
    end
  end

  def xlsx_sheet_rows(sheet_xml, shared_strings)
    document = REXML::Document.new(sheet_xml)
    namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
    raw_rows = []

    REXML::XPath.each(document, "//xmlns:sheetData/xmlns:row", namespaces) do |row|
      values = []

      REXML::XPath.each(row, "xmlns:c", namespaces) do |cell|
        column_index = cell.attribute("r").to_s[/[A-Z]+/].chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
        values[column_index] = xlsx_cell_value(cell, shared_strings)
      end

      raw_rows << values
    end

    rows_from_raw(raw_rows)
  end

  def rows_from_raw(raw_rows)
    header_index = raw_rows.index do |row|
      normalized_headers = row.to_a.map { |header| normalize_header(header) }
      normalized_headers.include?("project id") && normalized_headers.include?("project title")
    end

    raise ArgumentError, "Project Information Sheet headers were not found." if header_index.blank?

    headers = raw_rows[header_index].to_a.map { |header| header.to_s.squish }

    raw_rows[(header_index + 1)..].to_a.filter_map do |values|
      next if values.to_a.all? { |value| value.to_s.squish.blank? }

      headers.zip(values).to_h
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

  def attributes_for(row)
    attributes = {}
    yearly_amounts = {}

    normalized_row(row).each do |header, value|
      financial_year = ReportFinancialYear.normalize(header)
      if financial_year.present?
        yearly_amounts[financial_year] = money(value).to_s("F")
        next
      end

      attribute = HEADER_MAP[header]
      next unless attribute

      attributes[attribute] = date_attribute?(attribute) ? parse_date(value) : value.to_s.squish
    end

    attributes[:yearly_amounts] = yearly_amounts
    attributes[:total] = money(attributes[:total].presence || yearly_amounts.values.sum { |amount| BigDecimal(amount) })
    attributes
  end

  def normalized_row(row)
    row.to_h.transform_keys { |key| normalize_header(key) }
  end

  def normalize_header(value)
    value.to_s
      .squish
      .downcase
      .gsub(/[._]+/, " ")
      .gsub(/[^a-z0-9\- ]+/, "")
      .gsub(/\s+/, " ")
      .strip
  end

  def date_attribute?(attribute)
    %i[start_date end_date].include?(attribute)
  end

  def parse_date(value)
    text = value.to_s.squish
    return nil if text.blank?

    Date.parse(text)
  rescue ArgumentError
    nil
  end

  def money(value)
    BigDecimal(value.to_s.delete(",").presence || "0")
  rescue ArgumentError
    0.to_d
  end
end

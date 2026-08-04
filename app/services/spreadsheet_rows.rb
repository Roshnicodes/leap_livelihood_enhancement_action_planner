require "csv"
require "rexml/document"
require "zip"

class SpreadsheetRows
  def self.read(path, sheet: :all)
    new(path, sheet: sheet).read
  end

  def initialize(path, sheet: :all)
    @path = path
    @sheet = sheet
  end

  def read
    return csv_rows if File.extname(@path).casecmp(".csv").zero?

    xlsx_rows
  end

  private

  def csv_rows
    CSV.read(@path, headers: true, encoding: "bom|utf-8").map(&:to_h)
  end

  def xlsx_rows
    Zip::File.open(@path) do |zip|
      shared_strings = xlsx_shared_strings(zip)
      rows = []

      entries = zip.glob("xl/worksheets/sheet*.xml").sort_by(&:name)
      entries = entries.first(1) if @sheet == :first

      entries.each do |entry|
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

    format_xlsx_number(value.to_s)
  end

  def format_xlsx_number(raw)
    text = raw.to_s.squish
    return text if text.blank?

    ActionPlanRow.format_decimal_string(text)
  end
end

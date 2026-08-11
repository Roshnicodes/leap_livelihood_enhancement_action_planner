require "csv"
require "rexml/document"
require "tempfile"
require "zip"

class PbSourceFileUpdater
  ALLOCATED_HEADERS = [ "BLI Allocated Fund", "Project BLI Allocated Fund" ].freeze
  REMAINING_HEADERS = [ "BLI Remaining Fund" ].freeze
  MONTH_HEADERS = {
    apr: "Apr",
    may: "May",
    jun: "Jun",
    jul: "Jul",
    aug: "Aug",
    sep: "Sep",
    oct: "Oct",
    nov: "Nov",
    dec: "Dec",
    jan: "Jan",
    feb: "Feb",
    mar: "Mar"
  }.freeze

  def self.update_latest!(items)
    source_file = PbImportFile.ensure_latest_source!
    return unless source_file&.file_available?

    new(source_file, items).update!
  end

  def initialize(source_file, items)
    @source_file = source_file
    @items = Array(items).compact
  end

  def update!
    case File.extname(@source_file.absolute_path.to_s).downcase
    when ".csv"
      update_csv!
    else
      update_xlsx!
    end

    @source_file.update!(byte_size: File.size(@source_file.absolute_path))
  end

  private

  def update_csv!
    path = @source_file.absolute_path.to_s
    rows = CSV.read(path, headers: true, encoding: "bom|utf-8").map(&:to_h)
    headers = rows.first&.keys || []
    allocated_header = first_present_header(headers, ALLOCATED_HEADERS)
    remaining_header = first_present_header(headers, REMAINING_HEADERS)
    month_headers = ensure_csv_month_headers!(headers, rows)
    return unless allocated_header || remaining_header || month_headers.present?

    rows.each do |row|
      item = item_for_source_row(row)
      row[allocated_header] = amount_text(item.changed_total) if item && allocated_header
      row[remaining_header] = amount_text(item.changed_total) if item && remaining_header
      MONTH_HEADERS.each_key do |month|
        next unless month_headers[month]

        row[month_headers[month]] = item ? amount_text(item.public_send(month)) : nil
      end
    end

    CSV.open(path, "w", write_headers: true, headers: headers) do |csv|
      rows.each { |row| csv << headers.map { |header| row[header] } }
    end
  end

  def update_xlsx!
    source_path = @source_file.absolute_path.to_s
    temp_file = Tempfile.new([ "pb_source", ".xlsx" ], Rails.root.join("tmp"))

    Zip::File.open(source_path) do |input_zip|
      shared_strings = xlsx_shared_strings(input_zip)

      Zip::OutputStream.open(temp_file.path) do |output_zip|
        input_zip.each do |entry|
          output_zip.put_next_entry(entry.name)
          if entry.name.match?(%r{\Axl/worksheets/sheet\d+\.xml\z})
            output_zip.write updated_sheet_xml(input_zip.read(entry.name), shared_strings)
          else
            output_zip.write input_zip.read(entry.name)
          end
        end
      end
    end

    FileUtils.mv(temp_file.path, source_path)
  ensure
    temp_file&.close
    temp_file&.unlink if temp_file&.path && File.exist?(temp_file.path)
  end

  def updated_sheet_xml(sheet_xml, shared_strings)
    document = REXML::Document.new(sheet_xml)
    namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
    rows = REXML::XPath.match(document, "//xmlns:sheetData/xmlns:row", namespaces)
    header = nil

    rows.each do |row|
      values = xlsx_row_values(row, shared_strings)
      if header.blank?
        header = header_mapping(values)
        ensure_xlsx_month_headers!(row, header)
        next
      end
      next unless header

      item = item_for_source_values(values, header)
      write_number_cell(row, header[:allocated_column], item.changed_total) if item && header[:allocated_column]
      write_number_cell(row, header[:remaining_column], item.changed_total) if item && header[:remaining_column]
      MONTH_HEADERS.each_key do |month|
        next unless header[:month_columns][month]

        if item
          write_number_cell(row, header[:month_columns][month], item.public_send(month))
        else
          clear_cell(row, header[:month_columns][month])
        end
      end
    end

    xml = +""
    document.write(xml)
    xml
  end

  def header_mapping(values)
    normalized = values.each_with_index.to_h { |value, index| [ normalize_header(value), index ] }
    allocated = ALLOCATED_HEADERS.lazy.filter_map { |header| normalized[normalize_header(header)] }.first
    remaining = REMAINING_HEADERS.lazy.filter_map { |header| normalized[normalize_header(header)] }.first
    month_columns = MONTH_HEADERS.transform_values { |header| normalized[normalize_header(header)] }
    return unless allocated || remaining || month_columns.values.compact.present?

    {
      headers: normalized,
      allocated_column: allocated,
      remaining_column: remaining,
      month_columns: month_columns
    }
  end

  def ensure_csv_month_headers!(headers, rows)
    month_headers = MONTH_HEADERS.transform_values do |header|
      first_present_header(headers, [ header ])
    end

    MONTH_HEADERS.each_value do |header|
      next if month_headers.value?(header)

      headers << header
      rows.each { |row| row[header] ||= nil }
      month_headers[MONTH_HEADERS.key(header)] = header
    end

    month_headers
  end

  def ensure_xlsx_month_headers!(row, header)
    next_column = [
      header[:headers].values.max,
      header[:allocated_column],
      header[:remaining_column],
      *header[:month_columns].values
    ].compact.max.to_i + 1

    MONTH_HEADERS.each do |month, label|
      next if header[:month_columns][month]

      write_text_cell(row, next_column, label)
      header[:headers][normalize_header(label)] = next_column
      header[:month_columns][month] = next_column
      next_column += 1
    end
  end

  def xlsx_row_values(row, shared_strings)
    values = []
    namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }

    REXML::XPath.each(row, "xmlns:c", namespaces) do |cell|
      index = column_index(cell.attribute("r").to_s[/[A-Z]+/])
      values[index] = xlsx_cell_value(cell, shared_strings)
    end

    values
  end

  def write_number_cell(row, column_index, amount)
    cell = xlsx_cell_for(row, column_index)
    cell.delete_attribute("t")
    cell.delete_attribute("s")
    cell.elements.each { |element| cell.delete_element(element) }
    cell.add_element("v").text = amount_text(amount)
  end

  def write_text_cell(row, column_index, text)
    cell = xlsx_cell_for(row, column_index)
    cell.add_attribute("t", "inlineStr")
    cell.delete_attribute("s")
    cell.elements.each { |element| cell.delete_element(element) }
    cell.add_element("is").add_element("t").text = text.to_s
  end

  def clear_cell(row, column_index)
    cell = xlsx_cell_for(row, column_index)
    cell.delete_attribute("t")
    cell.delete_attribute("s")
    cell.elements.each { |element| cell.delete_element(element) }
  end

  def xlsx_cell_for(row, column_index)
    reference = "#{column_letters(column_index)}#{row.attribute("r")}"
    namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
    existing = REXML::XPath.first(row, "xmlns:c[@r='#{reference}']", namespaces)
    return existing if existing

    row.add_element("c", { "r" => reference })
  end

  def xlsx_shared_strings(zip)
    return [] unless zip.find_entry("xl/sharedStrings.xml")

    document = REXML::Document.new(zip.read("xl/sharedStrings.xml"))
    namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
    REXML::XPath.match(document, "//xmlns:si", namespaces).map do |item|
      REXML::XPath.match(item, ".//xmlns:t", namespaces).map(&:text).join
    end
  end

  def xlsx_cell_value(cell, shared_strings)
    type = cell.attribute("t").to_s
    namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
    value = REXML::XPath.first(cell, "xmlns:v", namespaces)&.text
    return shared_strings[value.to_i].to_s if type == "s"
    return REXML::XPath.match(cell, ".//xmlns:t", namespaces).map(&:text).join if type == "inlineStr"

    value.to_s
  end

  def item_for_source_row(row)
    item_for_source_values(row.values, header_mapping(row.keys))
  end

  def item_for_source_values(values, header)
    items_by_group[source_group_key(values, header)]
  end

  def source_group_key(values, header)
    [
      project_label(values, header),
      activity_label(values, header),
      vertical_label(values, header)
    ].map { |part| normalize_key(part) }
  end

  def value(values, header, *names)
    names.lazy.filter_map do |name|
      index = header[:headers][normalize_header(name)]
      index.nil? ? nil : values[index]
    end.first.to_s.squish
  end

  def project_label(values, header)
    project = value(values, header, "Project Name 2", "Project Name")
    return "Corteva (Existing & (New FPO)" if project.casecmp("Corteva").zero?

    project
  end

  def activity_label(values, header)
    value(values, header, "Activity", "ASA Activity", "Name", "Project Name", "BLI Code", "Project BLI Code").presence || "Untitled activity"
  end

  def vertical_label(values, header)
    value(values, header, "Parent Activity", "Vertical")
  end

  def items_by_group
    @items_by_group ||= @items
      .group_by { |item| [ item.project_name, item.activity_name, item.vertical_name ].map { |part| normalize_key(part) } }
      .filter_map { |key, grouped| [ key, grouped.first ] if grouped.one? }
      .to_h
  end

  def first_present_header(headers, candidates)
    normalized = headers.index_by { |header| normalize_header(header) }
    candidates.lazy.filter_map { |candidate| normalized[normalize_header(candidate)] }.first
  end

  def normalize_header(value)
    value.to_s.squish.downcase
  end

  def normalize_key(value)
    value.to_s.squish.downcase
  end

  def clean_code(value)
    code = value.to_s.squish
    return code unless code.match?(/\A-?\d+(\.\d+)?\z/)

    BigDecimal(code).round(4).to_s("F").sub(/\.?0+\z/, "")
  rescue ArgumentError
    code
  end

  def amount_text(amount)
    amount.to_d.round(2).to_s("F").sub(/\.0+\z/, "")
  end

  def decimal_value(value)
    BigDecimal(value.to_s.gsub(/[^0-9.-]/, "").presence || "0")
  rescue ArgumentError
    0.to_d
  end

  def column_index(letters)
    letters.to_s.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
  end

  def column_letters(index)
    letters = +""
    current = index

    loop do
      letters.prepend((65 + (current % 26)).chr)
      current = (current / 26) - 1
      break if current.negative?
    end

    letters
  end
end

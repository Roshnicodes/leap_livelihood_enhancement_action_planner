require "csv"
require "zip"

class XlsxWorkbook
  CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

  def self.from_csv(csv_data, title:, sheet_name: "Report")
    rows = CSV.parse(csv_data.to_s)
    headers = rows.shift || []

    new([
      {
        name: sheet_name,
        title: title,
        headers: headers,
        rows: rows,
        widths: inferred_widths(headers, rows)
      }
    ]).to_xlsx
  end

  def self.inferred_widths(headers, rows)
    headers.each_with_index.map do |header, index|
      values = rows.first(200).map { |row| row[index].to_s }
      [ [ header.to_s.length, *values.map(&:length) ].max + 4, 14 ].max.clamp(14, 42)
    end
  end

  def initialize(sheets)
    @sheets = sheets
  end

  def to_xlsx
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("[Content_Types].xml")
      zip.write content_types_xml
      zip.put_next_entry("_rels/.rels")
      zip.write root_relationships_xml
      zip.put_next_entry("xl/workbook.xml")
      zip.write workbook_xml
      zip.put_next_entry("xl/_rels/workbook.xml.rels")
      zip.write workbook_relationships_xml
      zip.put_next_entry("xl/styles.xml")
      zip.write styles_xml

      @sheets.each_with_index do |sheet, index|
        zip.put_next_entry("xl/worksheets/sheet#{index + 1}.xml")
        zip.write worksheet_xml(sheet)
      end
    end.string
  end

  private

  def worksheet_xml(sheet)
    rows = sheet.fetch(:rows)
    title = sheet[:title].presence || sheet[:name]
    generated_at = "Generated at #{Time.current.in_time_zone('Asia/Kolkata').strftime('%d %b %Y, %I:%M %p')}"
    all_rows = [
      { values: [ title ], style: 1 },
      { values: [ generated_at ], style: 2 },
      { values: [] },
      { values: sheet.fetch(:headers), style: 3 },
      *rows.map { |row| { values: row, style: nil } }
    ]
    last_column = [ sheet.fetch(:headers).size, rows.map(&:size).max.to_i, 1 ].max
    auto_filter_ref = "A4:#{cell_reference(last_column - 1, all_rows.size)}"

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetViews>
          <sheetView workbookViewId="0">
            <pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/>
          </sheetView>
        </sheetViews>
        #{columns_xml(sheet[:widths], last_column)}
        <sheetData>
          #{all_rows.each_with_index.map { |row, index| worksheet_row_xml(row, index + 1) }.join}
        </sheetData>
        <autoFilter ref="#{auto_filter_ref}"/>
      </worksheet>
    XML
  end

  def worksheet_row_xml(row, row_number)
    values = row.fetch(:values)
    cells = values.each_with_index.map do |value, index|
      cell_xml(value, cell_reference(index, row_number), row[:style])
    end.join
    height = row[:style] == 1 ? %( ht="24" customHeight="1") : ""
    %(<row r="#{row_number}"#{height}>#{cells}</row>)
  end

  def cell_xml(value, reference, style)
    style_attribute = style ? %( s="#{style}") : ""
    return %(<c r="#{reference}"#{style_attribute}/>) if value.nil?

    if numeric?(value)
      %(<c r="#{reference}"#{style_attribute}><v>#{value}</v></c>)
    else
      %(<c r="#{reference}" t="inlineStr"#{style_attribute}><is><t>#{escape_xml(value)}</t></is></c>)
    end
  end

  def numeric?(value)
    value.is_a?(Numeric)
  end

  def columns_xml(widths, last_column)
    widths = Array(widths)
    column_xml = last_column.times.map do |index|
      width = widths[index] || 16
      %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>)
    end.join

    "<cols>#{column_xml}</cols>"
  end

  def cell_reference(column_index, row_number)
    letters = +""
    index = column_index

    loop do
      letters.prepend((65 + (index % 26)).chr)
      index = (index / 26) - 1
      break if index.negative?
    end

    "#{letters}#{row_number}"
  end

  def content_types_xml
    sheet_overrides = @sheets.each_index.map do |index|
      %(<Override PartName="/xl/worksheets/sheet#{index + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>)
    end.join

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        #{sheet_overrides}
      </Types>
    XML
  end

  def root_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      </Relationships>
    XML
  end

  def workbook_xml
    sheets = @sheets.each_with_index.map do |sheet, index|
      %(<sheet name="#{escape_xml(sheet_name(sheet[:name], index))}" sheetId="#{index + 1}" r:id="rId#{index + 1}"/>)
    end.join

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>#{sheets}</sheets>
      </workbook>
    XML
  end

  def workbook_relationships_xml
    sheet_relationships = @sheets.each_index.map do |index|
      %(<Relationship Id="rId#{index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{index + 1}.xml"/>)
    end.join
    styles_id = @sheets.size + 1

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        #{sheet_relationships}
        <Relationship Id="rId#{styles_id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      </Relationships>
    XML
  end

  def styles_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="4">
          <font><sz val="10"/><name val="Aptos"/></font>
          <font><b/><sz val="14"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>
          <font><sz val="9"/><color rgb="FF667085"/><name val="Aptos"/></font>
          <font><b/><sz val="10"/><color rgb="FF102A43"/><name val="Aptos"/></font>
        </fonts>
        <fills count="4">
          <fill><patternFill patternType="none"/></fill>
          <fill><patternFill patternType="gray125"/></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FF075E57"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFE8F7F4"/><bgColor indexed="64"/></patternFill></fill>
        </fills>
        <borders count="2">
          <border><left/><right/><top/><bottom/><diagonal/></border>
          <border><left style="thin"><color rgb="FFD7E2EA"/></left><right style="thin"><color rgb="FFD7E2EA"/></right><top style="thin"><color rgb="FFD7E2EA"/></top><bottom style="thin"><color rgb="FFD7E2EA"/></bottom><diagonal/></border>
        </borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="4">
          <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
          <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
          <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          <xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
      </styleSheet>
    XML
  end

  def sheet_name(name, index)
    name.to_s.presence || "Sheet #{index + 1}"
  end

  def escape_xml(value)
    value.to_s.encode(xml: :text)
  end
end

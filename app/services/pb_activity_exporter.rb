require "zip"

class PbActivityExporter
  XLSX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
  COLUMNS = [
    [ "Stakeholder Name", :stakeholder_name ],
    [ "Allocating Date", :allocating_date ],
    [ "Project BLI Name", :name ],
    [ "BLI Code", :bli_code ],
    [ "BLI Allocated Fund", :allocated_fund ],
    [ "BLI Remaining Fund", :remaining_fund ],
    [ "Financial Year", :financial_year ],
    [ "Project Name", :project_name ],
    [ "Office Name", :office_name ],
    [ "Vertical", :vertical_name ],
    [ "Activity", :activity_name ],
    [ "Responsible Users", :responsible_user_name ],
    [ "Utilised Fund", :utilised_fund ],
    [ "Utilised (Approved) Fund", :approved_utilised_fund ],
    [ "Total PDO Count", :total_pdo_count ],
    [ "Total PDO Amount", :total_pdo_amount ],
    [ "Approved PDO Count", :approved_pdo_count ],
    [ "Approved PDO Amount", :approved_pdo_amount ],
    [ "Pending PDO Count", :pending_pdo_count ],
    [ "Pending PDO Amount", :pending_pdo_amount ],
    [ "Total RFP Count", :total_rfp_count ],
    [ "Total RFP Amount", :total_rfp_amount ],
    [ "Approved RFP Count", :approved_rfp_count ],
    [ "Approved RFP Amount", :approved_rfp_amount ],
    [ "Pending RFP Count", :pending_rfp_count ],
    [ "Pending RFP Amount", :pending_rfp_amount ]
  ].freeze

  def self.active_xlsx
    new(BliActivity.order(:project_name, :vertical_name, :bli_code, :id)).xlsx
  end

  def initialize(rows)
    @rows = rows
  end

  def xlsx
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("[Content_Types].xml")
      zip.write content_types_xml
      zip.put_next_entry("_rels/.rels")
      zip.write root_relationships_xml
      zip.put_next_entry("xl/workbook.xml")
      zip.write workbook_xml
      zip.put_next_entry("xl/_rels/workbook.xml.rels")
      zip.write workbook_relationships_xml
      zip.put_next_entry("xl/worksheets/sheet1.xml")
      zip.write worksheet_xml
    end.string
  end

  private

  def worksheet_xml
    rows = [ COLUMNS.map(&:first) ] + @rows.map { |row| COLUMNS.map { |(_header, attribute)| row.public_send(attribute) } }

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
          #{rows.each_with_index.map { |values, index| worksheet_row_xml(values, index + 1) }.join}
        </sheetData>
      </worksheet>
    XML
  end

  def worksheet_row_xml(values, row_number)
    cells = values.each_with_index.map { |value, index| cell_xml(value, cell_reference(index, row_number)) }.join
    %(<row r="#{row_number}">#{cells}</row>)
  end

  def cell_xml(value, reference)
    if value.is_a?(Numeric)
      %(<c r="#{reference}"><v>#{value}</v></c>)
    else
      %(<c r="#{reference}" t="inlineStr"><is><t>#{escape_xml(value)}</t></is></c>)
    end
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
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
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
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
          <sheet name="P&amp;B" sheetId="1" r:id="rId1"/>
        </sheets>
      </workbook>
    XML
  end

  def workbook_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      </Relationships>
    XML
  end

  def escape_xml(value)
    value.to_s.encode(xml: :text)
  end
end

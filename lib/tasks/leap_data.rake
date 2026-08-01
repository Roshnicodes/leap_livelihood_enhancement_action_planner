namespace :leap do
  def leap_xlsx_rows(path)
    require "rexml/document"
    require "zip"

    Zip::File.open(path) do |zip|
      shared_strings = []

      if (entry = zip.find_entry("xl/sharedStrings.xml"))
        document = REXML::Document.new(zip.read(entry.name))
        namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }

        REXML::XPath.each(document, "//xmlns:si", namespaces) do |item|
          shared_strings << REXML::XPath.match(item, ".//xmlns:t", namespaces).map(&:text).join
        end
      end

      sheet = zip.glob("xl/worksheets/sheet*.xml").sort_by(&:name).first
      document = REXML::Document.new(zip.read(sheet.name))
      namespaces = { "xmlns" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }
      rows = []

      REXML::XPath.each(document, "//xmlns:sheetData/xmlns:row", namespaces) do |row|
        values = []

        REXML::XPath.each(row, "xmlns:c", namespaces) do |cell|
          column_index = cell.attribute("r").to_s[/[A-Z]+/].chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
          type = cell.attribute("t").to_s
          value = REXML::XPath.first(cell, "xmlns:v", namespaces)&.text.to_s
          values[column_index] = type == "s" ? shared_strings[value.to_i].to_s : value
        end

        rows << values
      end

      headers = rows.shift.to_a.map { |header| header.to_s.squish }
      rows.map { |values| headers.zip(values).to_h }
    end
  end

  def leap_vertical_percent_for_source(source_parent_activity, verticals_by_name)
    source_name = source_parent_activity.to_s.squish
    existing_vertical = verticals_by_name[source_name.downcase]
    return existing_vertical if existing_vertical

    return unless source_name.start_with?("Com. Trng. Tools & Materials - General")

    base_vertical = verticals_by_name["Com. Trng. Tools & Materials - General".downcase]
    return unless base_vertical

    vertical = VerticalPercent.create!(
      vertical_name: source_name,
      total: base_vertical.total,
      apr: base_vertical.apr,
      may: base_vertical.may,
      jun: base_vertical.jun,
      jul: base_vertical.jul,
      aug: base_vertical.aug,
      sep: base_vertical.sep,
      oct: base_vertical.oct,
      nov: base_vertical.nov,
      dec: base_vertical.dec,
      jan: base_vertical.jan,
      feb: base_vertical.feb,
      mar: base_vertical.mar
    )
    verticals_by_name[source_name.downcase] = vertical
  end

  desc "Import Book4 parent-activity-to-employee assignments. Usage: FILE=/path/Book4.xlsx bundle exec rails leap:import_parent_activity_assignments"
  task import_parent_activity_assignments: :environment do
    file_path = ENV.fetch("FILE", "/home/asa/Downloads/Book4.xlsx")
    abort "Missing assignment file: #{file_path}" unless File.exist?(file_path)

    rows = leap_xlsx_rows(file_path)
    verticals_by_name = VerticalPercent.all.index_by { |vertical| vertical.vertical_name.squish.downcase }
    imported = 0

    ParentActivityAssignment.transaction do
      ParentActivityAssignment.delete_all
      EmployeeVerticalMapping.delete_all if ENV.fetch("REPLACE_EMPLOYEE_VERTICALS", "true") == "true"

      rows.each do |row|
        source_parent_activity = row["Parent Activity"].to_s.squish
        employee_code = row["Employee ID"].to_s.squish.sub(/\.0\z/, "")
        next if source_parent_activity.blank? || employee_code.blank?

        employee = Employee.find_by!(employee_code: employee_code)
        vertical_percent = leap_vertical_percent_for_source(source_parent_activity, verticals_by_name)
        abort "No vertical percent found for #{source_parent_activity.inspect}" unless vertical_percent

        employee.update!(active: true) unless employee.active?
        ParentActivityAssignment.create!(
          source_parent_activity: source_parent_activity,
          employee: employee,
          vertical_percent: vertical_percent
        )
        EmployeeVerticalMapping.find_or_create_by!(employee: employee, vertical_percent: vertical_percent)
        imported += 1
      end
    end

    puts "Imported #{imported} parent activity assignments from #{file_path}"
  end

  desc "Show employee to vertical mappings"
  task show_mappings: :environment do
    Employee.where(active: true).order(:employee_code).each do |employee|
      puts [
        employee.employee_code,
        employee.name,
        "verticals=#{employee.mapped_vertical_names.join(", ")}",
        "rows=#{employee.bli_activities.count}",
        "total=#{employee.bli_activities.sum(:allocated_fund).to_f.round(2)}"
      ].join(" | ")
    end
  end

  desc "Replace one employee's vertical mappings. Usage: EMPLOYEE_CODE=939 VERTICALS='A,B' bundle exec rails leap:set_employee_verticals"
  task set_employee_verticals: :environment do
    employee_code = ENV.fetch("EMPLOYEE_CODE")
    vertical_names = ENV.fetch("VERTICALS").split(",").map(&:squish).reject(&:blank?)
    employee = Employee.find_by!(employee_code: employee_code)

    EmployeeVerticalMapping.transaction do
      employee.employee_vertical_mappings.destroy_all

      vertical_names.each do |vertical_name|
        vertical_percent = VerticalPercent.find_by!(vertical_name: vertical_name)
        EmployeeVerticalMapping.create!(employee: employee, vertical_percent: vertical_percent)
      end
    end

    puts "#{employee.employee_code} #{employee.name}: #{employee.mapped_vertical_names.join(", ")}"
  end

  desc "Rebuild BLI activities from current employee_vertical_mappings"
  task sync_bli: :environment do
    csv_path = ENV.fetch("BLI_CSV_PATH", BliActivitySync::DEFAULT_CSV_PATH)
    xlsx_path = ENV.fetch("BLI_XLSX_PATH", BliActivitySync::DEFAULT_XLSX_PATH)
    financial_year = ENV.fetch("BLI_FINANCIAL_YEAR", BliActivitySync::DEFAULT_FINANCIAL_YEAR)

    count = BliActivitySync.new(
      csv_path: csv_path,
      xlsx_path: xlsx_path,
      financial_year: financial_year
    ).call(clear_summaries: ENV.fetch("CLEAR_SUMMARIES", "false") == "true")

    puts "Synced #{count} BLI activities for #{financial_year}."
  end
end

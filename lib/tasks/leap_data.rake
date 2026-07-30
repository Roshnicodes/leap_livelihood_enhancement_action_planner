namespace :leap do
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

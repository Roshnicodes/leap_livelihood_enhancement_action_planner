class ParentActivityAssignmentImporter
  def initialize(file_path:, replace_employee_verticals: true)
    @file_path = file_path
    @replace_employee_verticals = replace_employee_verticals
  end

  def import!
    rows = SpreadsheetRows.read(file_path, sheet: :first)
    verticals_by_name = VerticalPercent.all.index_by { |vertical| normalized(vertical.vertical_name) }
    imported = 0

    ParentActivityAssignment.transaction do
      ParentActivityAssignment.delete_all
      EmployeeVerticalMapping.delete_all if replace_employee_verticals

      rows.each do |row|
        source_parent_activity = row_value(row, "Parent Activity")
        employee_code = clean_employee_code(row_value(row, "Employee ID", "Employee Code"))
        next if source_parent_activity.blank? || employee_code.blank?

        employee = Employee.find_by!(employee_code: employee_code)
        vertical_percent = vertical_percent_for(source_parent_activity, verticals_by_name)
        raise ActiveRecord::RecordNotFound, "No vertical percent found for #{source_parent_activity.inspect}" unless vertical_percent

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

    imported
  end

  private

  attr_reader :file_path, :replace_employee_verticals

  def vertical_percent_for(source_parent_activity, verticals_by_name)
    source_name = source_parent_activity.to_s.squish
    existing_vertical = verticals_by_name[normalized(source_name)]
    return existing_vertical if existing_vertical
    return unless source_name.start_with?("Com. Trng. Tools & Materials - General")

    base_vertical = verticals_by_name[normalized("Com. Trng. Tools & Materials - General")]
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
    verticals_by_name[normalized(source_name)] = vertical
  end

  def row_value(row, *headers)
    normalized_row = row.transform_keys { |key| normalized(key) }
    headers.each do |header|
      value = normalized_row[normalized(header)]
      return value.to_s.squish if value.present?
    end
    nil
  end

  def clean_employee_code(value)
    value.to_s.squish.sub(/\.0\z/, "")
  end

  def normalized(value)
    value.to_s.squish.downcase
  end
end

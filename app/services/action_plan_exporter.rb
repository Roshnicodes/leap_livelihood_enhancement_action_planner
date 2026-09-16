require "csv"

class ActionPlanExporter
  PROJECT_OWNERSHIP_COLUMNS = [
    [ "PO_ID", :po_id ],
    [ "Project", :project_name ],
    [ "Project_owner_id", :project_owner_id ],
    [ "PO_Name", :po_name ],
    [ "Email_Id", :email_id ]
  ].freeze
  VERTICAL_MAPPING_COLUMNS = [
    [ "State", :state_code ],
    [ "ASA_Theme_ID", :asa_theme_id ],
    [ "ASA_Theme", :asa_theme ],
    [ "emp_name", :employee_name ],
    [ "emp_id", :employee_code ]
  ].freeze

  def self.active_csv
    new(ActionPlanRow.active_import.order(:id)).csv
  end

  def self.project_ownerships_csv
    CSV.generate(headers: true) do |csv|
      csv << PROJECT_OWNERSHIP_COLUMNS.map(&:first)

      ProjectOwnership.active.order(:po_id, :project_name).each do |ownership|
        csv << PROJECT_OWNERSHIP_COLUMNS.map { |(_header, attribute)| ownership.public_send(attribute) }
      end
    end
  end

  def self.vertical_mappings_csv
    CSV.generate(headers: true) do |csv|
      csv << VERTICAL_MAPPING_COLUMNS.map(&:first)

      ActionPlanVerticalMapping.active.includes(:employee).order(:state_code, :asa_theme_id, :employee_code).each do |mapping|
        csv << VERTICAL_MAPPING_COLUMNS.map do |(_header, attribute)|
          attribute == :employee_name ? mapping.employee&.name : mapping.public_send(attribute)
        end
      end
    end
  end

  def initialize(rows)
    @rows = rows
  end

  def csv
    CSV.generate(headers: true) do |csv|
      csv << ActionPlanRow::EXPORT_COLUMNS.map { |column| column[:header] }

      @rows.each do |row|
        csv << ActionPlanRow::EXPORT_COLUMNS.map do |column|
          if column[:total_method]
            row.public_send(column[:total_method])
          else
            row.public_send(column[:attribute])
          end
        end
      end
    end
  end
end

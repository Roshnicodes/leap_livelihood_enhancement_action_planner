require "csv"

class ActionPlanExporter
  def self.active_csv
    new(ActionPlanRow.active_import.order(:id)).csv
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

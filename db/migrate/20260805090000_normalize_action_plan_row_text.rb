require "cgi"

class NormalizeActionPlanRowText < ActiveRecord::Migration[8.1]
  TEXT_COLUMNS = %w[
    statte project_name project_owner user_name to_name theme activity
    unit_type a_remark responsibel asa_theme asa_activity_name
  ].freeze

  ENTITY_PATTERN = "&(amp|lt|gt|quot|apos|nbsp|#[0-9]+);".freeze
  MAX_UNESCAPE_PASSES = 5

  class MigrationActionPlanRow < ActiveRecord::Base
    self.table_name = "action_plan_rows"
  end

  def up
    columns = TEXT_COLUMNS & MigrationActionPlanRow.column_names

    columns.each do |column|
      scope = MigrationActionPlanRow.where("#{column} ~ ?", ENTITY_PATTERN)

      scope.select(:id, column).find_in_batches(batch_size: 500) do |batch|
        batch.each do |record|
          cleaned = unescape(record[column])
          next if cleaned == record[column]

          MigrationActionPlanRow.where(id: record.id).update_all(column => cleaned)
        end
      end
    end
  end

  def down
    # Restoring the escaped text would only reintroduce the corruption.
  end

  private

  def unescape(raw)
    text = raw.to_s

    MAX_UNESCAPE_PASSES.times do
      unescaped = CGI.unescapeHTML(text.gsub("&#160;", " ").gsub("&nbsp;", " "))
      break if unescaped == text

      text = unescaped
    end

    text.squish
  end
end

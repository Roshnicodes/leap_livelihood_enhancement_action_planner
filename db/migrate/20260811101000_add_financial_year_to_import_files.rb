class AddFinancialYearToImportFiles < ActiveRecord::Migration[8.1]
  def up
    add_column :action_plan_import_files, :financial_year, :string
    add_column :pb_import_files, :financial_year, :string

    backfill_financial_year(:action_plan_import_files)
    backfill_financial_year(:pb_import_files)

    change_column_null :action_plan_import_files, :financial_year, false
    change_column_null :pb_import_files, :financial_year, false

    add_index :action_plan_import_files, :financial_year
    add_index :pb_import_files, :financial_year
  end

  def down
    remove_index :pb_import_files, :financial_year
    remove_index :action_plan_import_files, :financial_year
    remove_column :pb_import_files, :financial_year
    remove_column :action_plan_import_files, :financial_year
  end

  private

  def backfill_financial_year(table_name)
    execute <<~SQL.squish
      UPDATE #{table_name}
      SET financial_year =
        CASE
          WHEN EXTRACT(MONTH FROM imported_at) >= 4
            THEN EXTRACT(YEAR FROM imported_at)::int || '-' || (EXTRACT(YEAR FROM imported_at)::int + 1)
          ELSE
            (EXTRACT(YEAR FROM imported_at)::int - 1) || '-' || EXTRACT(YEAR FROM imported_at)::int
        END
    SQL
  end
end

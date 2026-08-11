class UpdateBudgetUtilizationsUniqueScope < ActiveRecord::Migration[8.1]
  def up
    if index_exists?(:budget_utilizations, [ :project_name, :activity_name, :vertical_name, :month ], name: "idx_budget_utilizations_unique_scope")
      remove_index :budget_utilizations, name: "idx_budget_utilizations_unique_scope"
    end

    dedupe_budget_utilizations!

    unless index_exists?(:budget_utilizations, [ :project_name, :bli_code, :month ], name: "idx_budget_utilizations_unique_scope")
      add_index :budget_utilizations,
        [ :project_name, :bli_code, :month ],
        unique: true,
        name: "idx_budget_utilizations_unique_scope"
    end
  end

  def down
    if index_exists?(:budget_utilizations, [ :project_name, :bli_code, :month ], name: "idx_budget_utilizations_unique_scope")
      remove_index :budget_utilizations, name: "idx_budget_utilizations_unique_scope"
    end

    unless index_exists?(:budget_utilizations, [ :project_name, :activity_name, :vertical_name, :month ], name: "idx_budget_utilizations_unique_scope")
      add_index :budget_utilizations,
        [ :project_name, :activity_name, :vertical_name, :month ],
        unique: true,
        name: "idx_budget_utilizations_unique_scope"
    end
  end

  private

  def dedupe_budget_utilizations!
    say_with_time "dedupe budget_utilizations by project_name, bli_code, month" do
      duplicates = select_all(<<~SQL.squish)
        SELECT project_name, bli_code, month
        FROM budget_utilizations
        GROUP BY project_name, bli_code, month
        HAVING COUNT(*) > 1
      SQL

      duplicates.each do |row|
        keep_id = select_value(<<~SQL.squish)
          SELECT id
          FROM budget_utilizations
          WHERE project_name = #{quote(row["project_name"])}
            AND bli_code IS NOT DISTINCT FROM #{quote(row["bli_code"])}
            AND month = #{quote(row["month"])}
          ORDER BY utilized_amount DESC, updated_at DESC NULLS LAST, id DESC
          LIMIT 1
        SQL

        execute(<<~SQL.squish)
          DELETE FROM budget_utilizations
          WHERE project_name = #{quote(row["project_name"])}
            AND bli_code IS NOT DISTINCT FROM #{quote(row["bli_code"])}
            AND month = #{quote(row["month"])}
            AND id <> #{keep_id.to_i}
        SQL
      end

      duplicates.length
    end
  end
end

class AddDraftStatusToBudgetUtilizations < ActiveRecord::Migration[8.1]
  def change
    add_column :budget_utilizations, :status, :string, default: "draft", null: false
    add_column :budget_utilizations, :submitted_at, :datetime
    add_reference :budget_utilizations, :submitted_by, foreign_key: { to_table: :users }

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE budget_utilizations
          SET status = 'submitted',
              submitted_at = updated_at,
              submitted_by_id = updated_by_id
        SQL
      end
    end

    add_index :budget_utilizations, :status
    add_index :budget_utilizations, [ :project_name, :month, :status ]
  end
end

class CreateBudgetUtilizations < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_utilizations do |t|
      t.string :project_name, null: false
      t.string :activity_name, null: false
      t.string :vertical_name, null: false
      t.string :bli_code
      t.string :month, null: false
      t.decimal :planned_amount, precision: 15, scale: 2, default: 0, null: false
      t.decimal :utilized_amount, precision: 15, scale: 2, default: 0, null: false
      t.text :remark
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :budget_utilizations,
      [ :project_name, :activity_name, :vertical_name, :month ],
      unique: true,
      name: "idx_budget_utilizations_unique_scope"
    add_index :budget_utilizations, [ :project_name, :month ]
    add_index :budget_utilizations, :month
  end
end

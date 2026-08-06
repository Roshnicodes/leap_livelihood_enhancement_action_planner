class CreateActionPlanFcoMappings < ActiveRecord::Migration[8.1]
  def up
    create_table :action_plan_fco_mappings do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :employee_code, null: false
      t.string :fco_id, null: false
      t.string :fco_name, null: false

      t.timestamps
    end

    add_index :action_plan_fco_mappings, :employee_code
    add_index :action_plan_fco_mappings, :fco_id
    add_index :action_plan_fco_mappings, [ :employee_id, :fco_id ], unique: true, name: "idx_action_plan_fco_employee_fco"

    execute <<~SQL.squish
      INSERT INTO action_plan_fco_mappings (employee_id, employee_code, fco_id, fco_name, created_at, updated_at)
      SELECT employees.id, employees.employee_code, '20', COALESCE(NULLIF(action_plan_rows.user_name, ''), 'Shahdol - FCO'), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM employees
      JOIN action_plan_rows ON action_plan_rows.user_id = '20' AND action_plan_rows.import_flag = 0
      WHERE employees.employee_code = '1087'
      LIMIT 1
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    drop_table :action_plan_fco_mappings
  end
end

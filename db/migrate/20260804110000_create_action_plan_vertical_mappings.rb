class CreateActionPlanVerticalMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :action_plan_vertical_mappings do |t|
      t.references :employee, foreign_key: true
      t.string :employee_code, null: false
      t.string :state_code, null: false
      t.string :asa_theme_id, null: false
      t.text :asa_theme

      t.timestamps
    end

    add_index :action_plan_vertical_mappings,
      [ :employee_code, :state_code, :asa_theme_id ],
      unique: true,
      name: "idx_action_plan_vertical_mappings_unique"
    add_index :action_plan_vertical_mappings, [ :employee_id, :state_code, :asa_theme_id ], name: "idx_action_plan_vertical_mappings_employee_lookup"
  end
end

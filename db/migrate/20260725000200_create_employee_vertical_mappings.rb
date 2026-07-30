class CreateEmployeeVerticalMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :employee_vertical_mappings do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :vertical_percent, null: false, foreign_key: true

      t.timestamps
    end

    add_index :employee_vertical_mappings, [:employee_id, :vertical_percent_id], unique: true, name: "index_employee_vertical_mappings_unique"
  end
end

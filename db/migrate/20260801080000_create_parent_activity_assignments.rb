class CreateParentActivityAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :parent_activity_assignments do |t|
      t.string :source_parent_activity, null: false
      t.references :employee, null: false, foreign_key: true
      t.references :vertical_percent, null: false, foreign_key: true

      t.timestamps
    end

    add_index :parent_activity_assignments, :source_parent_activity, unique: true, name: "index_parent_activity_assignments_on_source"
    add_index :parent_activity_assignments, [:employee_id, :vertical_percent_id], name: "index_parent_activity_assignments_on_employee_vertical"
  end
end

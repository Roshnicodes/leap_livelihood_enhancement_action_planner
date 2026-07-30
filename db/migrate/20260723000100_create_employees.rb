class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      t.string :employee_code, null: false
      t.string :name, null: false
      t.string :office_name
      t.string :primary_vertical
      t.string :primary_project
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :employees, :employee_code, unique: true
    add_index :employees, :name
  end
end

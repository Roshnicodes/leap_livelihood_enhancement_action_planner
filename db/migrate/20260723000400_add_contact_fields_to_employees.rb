class AddContactFieldsToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_column :employees, :email, :string
    add_column :employees, :mobile_number, :string
    add_column :employees, :department, :string

    add_index :employees, :email
    add_index :employees, :department
  end
end

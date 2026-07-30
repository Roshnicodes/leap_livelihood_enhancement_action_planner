class AddJobFieldsToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_column :employees, :designation, :string
    add_column :employees, :functional_responsibility, :string
    add_column :employees, :branch, :string
    add_column :employees, :sub_branch, :string
  end
end

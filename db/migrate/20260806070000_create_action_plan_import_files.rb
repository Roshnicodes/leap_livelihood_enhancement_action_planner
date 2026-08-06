class CreateActionPlanImportFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :action_plan_import_files do |t|
      t.string :import_type, null: false
      t.string :original_filename, null: false
      t.string :content_type
      t.integer :byte_size, default: 0, null: false
      t.string :storage_path, null: false
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.integer :row_count
      t.string :status, default: "saved", null: false
      t.text :error_message
      t.datetime :imported_at, null: false

      t.timestamps
    end

    add_index :action_plan_import_files, :import_type
    add_index :action_plan_import_files, :status
    add_index :action_plan_import_files, :imported_at
    add_index :action_plan_import_files, :storage_path, unique: true
  end
end

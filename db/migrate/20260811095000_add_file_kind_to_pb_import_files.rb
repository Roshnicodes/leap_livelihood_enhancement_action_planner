class AddFileKindToPbImportFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :pb_import_files, :file_kind, :string, default: "source", null: false
    add_index :pb_import_files, :file_kind
  end
end

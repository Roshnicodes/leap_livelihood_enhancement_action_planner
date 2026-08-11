class AddApprovalFieldsToPbImportFiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :pb_import_files, :approved_by, foreign_key: { to_table: :users }
    add_column :pb_import_files, :approved_at, :datetime
  end
end

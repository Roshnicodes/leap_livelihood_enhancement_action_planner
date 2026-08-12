class CreateDonorReportUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :donor_report_types do |t|
      t.string :name, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :donor_report_types, :name, unique: true
    add_index :donor_report_types, :active

    create_table :donor_report_uploads do |t|
      t.string :project_name, null: false
      t.references :donor_report_type, null: false, foreign_key: true
      t.string :frequency, null: false
      t.date :submission_date, null: false
      t.references :uploaded_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :donor_report_uploads, :project_name
    add_index :donor_report_uploads, :frequency
    add_index :donor_report_uploads, :submission_date

    reversible do |dir|
      dir.up do
        default_report_types.each do |name|
          execute <<~SQL.squish
            INSERT INTO donor_report_types (name, active, created_at, updated_at)
            VALUES (#{connection.quote(name)}, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (name) DO NOTHING
          SQL
        end
      end
    end
  end

  private

  def default_report_types
    [
      "Financial Report",
      "Physical Progress Report"
    ]
  end
end

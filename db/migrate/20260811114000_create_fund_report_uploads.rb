class CreateFundReportUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :fund_report_types do |t|
      t.string :name, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :fund_report_types, :name, unique: true
    add_index :fund_report_types, :active

    create_table :fund_report_uploads do |t|
      t.string :project_name, null: false
      t.references :fund_report_type, null: false, foreign_key: true
      t.date :submission_letter_date, null: false
      t.decimal :submission_letter_amount, precision: 15, scale: 2, default: 0, null: false
      t.date :submission_receipt_date, null: false
      t.decimal :submission_receipt_amount, precision: 15, scale: 2, default: 0, null: false
      t.references :uploaded_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :fund_report_uploads, :project_name
    add_index :fund_report_uploads, :submission_letter_date
    add_index :fund_report_uploads, :submission_receipt_date

    reversible do |dir|
      dir.up do
        [ "Fund Submission Letter", "Fund Receipt Letter" ].each do |name|
          execute <<~SQL.squish
            INSERT INTO fund_report_types (name, active, created_at, updated_at)
            VALUES (#{connection.quote(name)}, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (name) DO NOTHING
          SQL
        end
      end
    end
  end
end

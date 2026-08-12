class CreatePisReportDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :pis_document_types do |t|
      t.string :name, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :pis_document_types, :name, unique: true
    add_index :pis_document_types, :active

    create_table :pis_report_documents do |t|
      t.string :project_name, null: false
      t.references :pis_document_type, null: false, foreign_key: true
      t.string :financial_year, null: false
      t.date :submission_date, null: false
      t.references :uploaded_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :pis_report_documents, :project_name
    add_index :pis_report_documents, :financial_year
    add_index :pis_report_documents, :submission_date

    reversible do |dir|
      dir.up do
        default_doc_types.each do |name|
          execute <<~SQL.squish
            INSERT INTO pis_document_types (name, active, created_at, updated_at)
            VALUES (#{connection.quote(name)}, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (name) DO NOTHING
          SQL
        end
      end
    end
  end

  private

  def default_doc_types
    [
      "Project Proposal",
      "Project Agreement",
      "List of Villages",
      "Project Area Map",
      "Project Budget",
      "Project PPT",
      "Photographs",
      "PIS",
      "DPR"
    ]
  end
end

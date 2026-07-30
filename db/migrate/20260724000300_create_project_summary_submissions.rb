class CreateProjectSummarySubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :project_summary_submissions do |t|
      t.references :employee, null: false, foreign_key: true
      t.decimal :total_amount, precision: 15, scale: 2, default: 0, null: false
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :project_summary_submissions, :submitted_at
  end
end

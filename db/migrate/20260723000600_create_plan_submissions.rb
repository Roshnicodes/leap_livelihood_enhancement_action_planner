class CreatePlanSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_submissions do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :mode, null: false
      t.string :filter_name, null: false
      t.decimal :original_total, precision: 15, scale: 2, default: 0, null: false
      t.decimal :changed_total, precision: 15, scale: 2, default: 0, null: false
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :plan_submissions, :mode
    add_index :plan_submissions, :submitted_at
  end
end

class CreateBliActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :bli_activities do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :stakeholder_name
      t.date :allocating_date
      t.string :name
      t.string :bli_code
      t.decimal :allocated_fund, precision: 15, scale: 2, default: 0, null: false
      t.decimal :remaining_fund, precision: 15, scale: 2, default: 0, null: false
      t.string :financial_year
      t.string :project_name
      t.string :office_name
      t.string :vertical_name
      t.string :parent_activity
      t.string :activity_name
      t.string :responsible_user_name
      t.decimal :utilised_fund, precision: 15, scale: 2, default: 0, null: false
      t.decimal :approved_utilised_fund, precision: 15, scale: 2, default: 0, null: false
      t.integer :total_pdo_count, default: 0, null: false
      t.decimal :total_pdo_amount, precision: 15, scale: 2, default: 0, null: false
      t.integer :approved_pdo_count, default: 0, null: false
      t.decimal :approved_pdo_amount, precision: 15, scale: 2, default: 0, null: false
      t.integer :pending_pdo_count, default: 0, null: false
      t.decimal :pending_pdo_amount, precision: 15, scale: 2, default: 0, null: false
      t.integer :total_rfp_count, default: 0, null: false
      t.decimal :total_rfp_amount, precision: 15, scale: 2, default: 0, null: false
      t.integer :approved_rfp_count, default: 0, null: false
      t.decimal :approved_rfp_amount, precision: 15, scale: 2, default: 0, null: false
      t.integer :pending_rfp_count, default: 0, null: false
      t.decimal :pending_rfp_amount, precision: 15, scale: 2, default: 0, null: false

      t.timestamps
    end

    add_index :bli_activities, :project_name
    add_index :bli_activities, :vertical_name
    add_index :bli_activities, :financial_year
  end
end

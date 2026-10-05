class CreateActionPlanFcoTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :action_plan_fco_transfers do |t|
      t.string :source_fco_id, null: false
      t.string :source_fco_name, null: false
      t.string :target_fco_id, null: false
      t.string :target_fco_name, null: false
      t.references :transferred_by, foreign_key: { to_table: :users }, null: false
      t.references :reverted_by, foreign_key: { to_table: :users }
      t.integer :action_plan_row_count, null: false, default: 0
      t.integer :project_count, null: false, default: 0
      t.integer :month_change_count, null: false, default: 0
      t.integer :historical_submission_count, null: false, default: 0
      t.jsonb :action_plan_row_ids, null: false, default: []
      t.jsonb :month_change_ids, null: false, default: []
      t.text :note
      t.datetime :reverted_at

      t.timestamps
    end

    add_index :action_plan_fco_transfers, :source_fco_id,
      unique: true,
      where: "reverted_at IS NULL",
      name: "idx_active_fco_transfer_source"
    add_index :action_plan_fco_transfers, :target_fco_id
    add_index :action_plan_fco_transfers, :reverted_at
  end
end

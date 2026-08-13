class CreateProjectInformationSheets < ActiveRecord::Migration[8.1]
  def change
    create_table :project_information_sheets do |t|
      t.string :project_id, null: false
      t.string :project_title
      t.string :donor
      t.string :category
      t.text :project_period
      t.jsonb :yearly_amounts, null: false, default: {}
      t.decimal :total, precision: 18, scale: 2, null: false, default: 0
      t.text :project_location
      t.string :project_area_map
      t.string :donor_reporting_officer
      t.date :start_date
      t.date :end_date
      t.text :project_objectives
      t.string :households_to_be_covered
      t.string :fco_name
      t.string :po
      t.string :reporting_system
      t.string :physical
      t.string :financial
      t.string :annexure
      t.references :uploaded_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :project_information_sheets, :project_id, unique: true
    add_index :project_information_sheets, :project_title
    add_index :project_information_sheets, :donor
    add_index :project_information_sheets, :updated_at
  end
end

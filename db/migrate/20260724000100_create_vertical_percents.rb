class CreateVerticalPercents < ActiveRecord::Migration[8.1]
  def change
    create_table :vertical_percents do |t|
      t.string :vertical_name, null: false
      t.decimal :total, precision: 8, scale: 2, default: 0, null: false
      t.decimal :apr, precision: 8, scale: 2, default: 0, null: false
      t.decimal :may, precision: 8, scale: 2, default: 0, null: false
      t.decimal :jun, precision: 8, scale: 2, default: 0, null: false
      t.decimal :jul, precision: 8, scale: 2, default: 0, null: false
      t.decimal :aug, precision: 8, scale: 2, default: 0, null: false
      t.decimal :sep, precision: 8, scale: 2, default: 0, null: false
      t.decimal :oct, precision: 8, scale: 2, default: 0, null: false
      t.decimal :nov, precision: 8, scale: 2, default: 0, null: false
      t.decimal :dec, precision: 8, scale: 2, default: 0, null: false
      t.decimal :jan, precision: 8, scale: 2, default: 0, null: false
      t.decimal :feb, precision: 8, scale: 2, default: 0, null: false
      t.decimal :mar, precision: 8, scale: 2, default: 0, null: false

      t.timestamps
    end

    add_index :vertical_percents, :vertical_name, unique: true
  end
end

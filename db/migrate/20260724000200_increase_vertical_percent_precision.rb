class IncreaseVerticalPercentPrecision < ActiveRecord::Migration[8.1]
  def change
    change_column :vertical_percents, :total, :decimal, precision: 10, scale: 6, default: 0, null: false
    VerticalPercent::MONTH_COLUMNS.each do |month|
      change_column :vertical_percents, month, :decimal, precision: 10, scale: 6, default: 0, null: false
    end
  end
end

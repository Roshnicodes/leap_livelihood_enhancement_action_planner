class AddPlannedTotalToActionPlanRows < ActiveRecord::Migration[8.1]
  MONTHS = %w[apr may jun jul aug sep oct nov dec jan feb mar].freeze

  def up
    add_column :action_plan_rows, :planned_total, :integer, default: 0, null: false

    month_sum = MONTHS.map { |month| "COALESCE(#{month}, 0)" }.join(" + ")
    execute "UPDATE action_plan_rows SET planned_total = #{month_sum}"
  end

  def down
    remove_column :action_plan_rows, :planned_total
  end
end

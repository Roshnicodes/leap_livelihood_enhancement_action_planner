class AddOriginalMonthTargetsToActionPlanRows < ActiveRecord::Migration[8.1]
  MONTHS = %w[apr may jun jul aug sep oct nov dec jan feb mar].freeze

  def up
    MONTHS.each do |month|
      add_column :action_plan_rows, "original_#{month}", :integer, default: 0, null: false
    end

    assignments = MONTHS.map { |month| "original_#{month} = COALESCE(#{month}, 0)" }.join(", ")
    execute "UPDATE action_plan_rows SET #{assignments}"
  end

  def down
    MONTHS.reverse_each do |month|
      remove_column :action_plan_rows, "original_#{month}"
    end
  end
end

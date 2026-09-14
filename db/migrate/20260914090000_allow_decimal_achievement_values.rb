class AllowDecimalAchievementValues < ActiveRecord::Migration[8.1]
  ACHIEVEMENT_COLUMNS = %i[apr_t may_t jun_t jul_t aug_t sep_t oct_t nov_t dec_t jan_t feb_t mar_t].freeze
  DECIMAL_OPTIONS = { precision: 12, scale: 2, default: 0, null: false }.freeze
  INTEGER_OPTIONS = { default: 0, null: false }.freeze

  def up
    ACHIEVEMENT_COLUMNS.each do |column|
      change_column :action_plan_rows, column, :decimal, **DECIMAL_OPTIONS
    end

    change_column :achievement_submission_rows, :achievement_value, :decimal, **DECIMAL_OPTIONS
  end

  def down
    ACHIEVEMENT_COLUMNS.each do |column|
      change_column :action_plan_rows, column, :integer, **INTEGER_OPTIONS
    end

    change_column :achievement_submission_rows, :achievement_value, :integer, **INTEGER_OPTIONS
  end
end

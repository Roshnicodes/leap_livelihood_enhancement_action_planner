class CorrectBinitFcoMappingToShahdol < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE action_plan_fco_mappings
      SET fco_id = '20',
          fco_name = COALESCE(
            (SELECT NULLIF(user_name, '') FROM action_plan_rows WHERE user_id = '20' AND import_flag = 0 LIMIT 1),
            'Shahdol - FCO'
          ),
          updated_at = CURRENT_TIMESTAMP
      WHERE employee_code = '1087'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE action_plan_fco_mappings
      SET fco_id = '9',
          fco_name = COALESCE(
            (SELECT NULLIF(user_name, '') FROM action_plan_rows WHERE user_id = '9' AND import_flag = 0 LIMIT 1),
            'Ambikapur - FCO'
          ),
          updated_at = CURRENT_TIMESTAMP
      WHERE employee_code = '1087'
    SQL
  end
end

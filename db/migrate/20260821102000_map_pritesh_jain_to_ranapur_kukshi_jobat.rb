class MapPriteshJainToRanapurKukshiJobat < ActiveRecord::Migration[8.1]
  FCO_MAPPINGS = [
    [ "16", "Jobat - FCO" ],
    [ "17", "Kukshi - FCO" ],
    [ "22", "Ranapur - FCO" ]
  ].freeze

  def up
    FCO_MAPPINGS.each do |fco_id, fco_name|
      execute <<~SQL.squish
        INSERT INTO action_plan_fco_mappings
          (employee_id, employee_code, fco_id, fco_name, created_at, updated_at)
        SELECT id, employee_code, #{quote(fco_id)}, #{quote(fco_name)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM employees
        WHERE employee_code = '25'
        ON CONFLICT (employee_id, fco_id) DO UPDATE
        SET fco_name = EXCLUDED.fco_name,
            employee_code = EXCLUDED.employee_code,
            updated_at = CURRENT_TIMESTAMP
      SQL
    end
  end

  def down
    execute <<~SQL.squish
      DELETE FROM action_plan_fco_mappings
      WHERE employee_code = '25'
        AND fco_id IN ('16', '17', '22')
    SQL
  end
end

class PopulateActionPlanFcoMappings < ActiveRecord::Migration[8.1]
  def up
    fcos = select_all(<<~SQL.squish).map { |row| { fco_id: row["user_id"].to_s.squish, fco_name: row["user_name"].to_s.squish } }
      SELECT DISTINCT user_id, user_name
      FROM action_plan_rows
      WHERE import_flag = 0
        AND user_id IS NOT NULL
        AND user_id <> ''
    SQL

    employees = select_all(<<~SQL.squish)
      SELECT id, employee_code, branch, sub_branch, office_name, email, designation
      FROM employees
      WHERE active = TRUE
    SQL

    employees.each do |employee|
      employee_tokens = employee_fco_tokens(employee)
      next if employee_tokens.blank?

      fcos.each do |fco|
        next unless token_match?(employee_tokens, fco_name_tokens(fco[:fco_name]))

        execute <<~SQL.squish
          INSERT INTO action_plan_fco_mappings
            (employee_id, employee_code, fco_id, fco_name, created_at, updated_at)
          VALUES
            (#{connection.quote(employee["id"])},
             #{connection.quote(employee["employee_code"])},
             #{connection.quote(fco[:fco_id])},
             #{connection.quote(fco[:fco_name])},
             CURRENT_TIMESTAMP,
             CURRENT_TIMESTAMP)
          ON CONFLICT (employee_id, fco_id) DO UPDATE
          SET employee_code = EXCLUDED.employee_code,
              fco_name = EXCLUDED.fco_name,
              updated_at = CURRENT_TIMESTAMP
        SQL
      end
    end
  end

  def down
    execute "DELETE FROM action_plan_fco_mappings"
  end

  private

  def employee_fco_tokens(employee)
    text = employee.values_at("branch", "sub_branch", "office_name", "email", "designation").compact.join(" ").downcase
    return [] unless text.include?("fco")

    tokens = []
    text.scan(/fco\s*[-_. ]+\s*([a-z]+)/) { |match| tokens << match.first }
    text.scan(/fco[._-]([a-z]+)/) { |match| tokens << match.first }
    text.scan(/pmu[._-]([a-z]+)/) { |match| tokens << match.first }
    normalize_tokens(tokens)
  end

  def fco_name_tokens(name)
    normalize_tokens(name.to_s.downcase.gsub(/\bfco\b/i, " ").split(/[^a-z0-9]+/))
  end

  def normalize_tokens(tokens)
    Array(tokens)
      .map { |token| token.to_s.downcase.gsub(/[^a-z0-9]/, "") }
      .reject { |token| token.blank? || %w[fco to sub team office direct reporting cisspo mp].include?(token) }
      .flat_map { |token| [ token, token.gsub("h", "") ] }
      .uniq
  end

  def token_match?(employee_tokens, fco_tokens)
    employee_tokens.any? do |employee_token|
      fco_tokens.any? do |fco_token|
        employee_token == fco_token ||
          (employee_token.length >= 5 && fco_token.include?(employee_token)) ||
          (fco_token.length >= 5 && employee_token.include?(fco_token))
      end
    end
  end
end

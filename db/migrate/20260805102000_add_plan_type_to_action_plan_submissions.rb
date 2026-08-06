class AddPlanTypeToActionPlanSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :action_plan_submissions, :plan_type, :string, null: false, default: "project"
    add_index :action_plan_submissions, [ :employee_id, :plan_type, :project_name, :submitted_at ],
      name: "idx_action_plan_submissions_employee_type_project"
    add_index :action_plan_submissions, [ :plan_type, :status, :current_stage ],
      name: "idx_action_plan_submissions_type_stage"
  end
end

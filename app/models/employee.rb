class Employee < ApplicationRecord
  has_one :user, dependent: :destroy
  has_many :bli_activities, dependent: :destroy
  has_many :plan_submissions, dependent: :destroy
  has_many :project_summary_submissions, dependent: :destroy
  has_many :project_summary_approvals, class_name: "ProjectSummarySubmission", foreign_key: :approver_id, dependent: :nullify
  has_many :action_plan_submissions, dependent: :destroy
  has_many :action_plan_vertical_mappings, dependent: :nullify
  has_many :po_action_plan_approvals, class_name: "ActionPlanSubmission", foreign_key: :po_approver_id, dependent: :nullify
  has_many :coo_action_plan_approvals, class_name: "ActionPlanSubmission", foreign_key: :coo_approver_id, dependent: :nullify
  has_many :director_action_plan_approvals, class_name: "ActionPlanSubmission", foreign_key: :director_approver_id, dependent: :nullify
  has_many :employee_vertical_mappings, dependent: :destroy
  has_many :mapped_vertical_percents, through: :employee_vertical_mappings, source: :vertical_percent
  has_many :parent_activity_assignments, dependent: :destroy

  validates :employee_code, presence: true, uniqueness: true
  validates :name, presence: true

  def verticals
    mapped_vertical_names.presence || bli_activities.distinct.order(:vertical_name).pluck(:vertical_name).compact_blank
  end

  def projects
    accessible_bli_activities.map(&:project_name).compact_blank.uniq.sort
  end

  def accessible_bli_activities
    bli_activities
      .order(:project_name, :vertical_name, :activity_name, :bli_code, :id)
      .to_a
  end

  def mapped_vertical_names
    mapped_vertical_percents.order(:vertical_name).pluck(:vertical_name)
  end

  def action_plan_vertical_names
    mapping_names = action_plan_vertical_mappings.order(:state_code, :asa_theme_id).map(&:label)
    return mapping_names if mapping_names.present?

    parent_activity_assignments.order(:source_parent_activity).pluck(:source_parent_activity).presence ||
      mapped_vertical_names
  end
end

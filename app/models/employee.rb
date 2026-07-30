class Employee < ApplicationRecord
  has_one :user, dependent: :destroy
  has_many :bli_activities, dependent: :destroy
  has_many :plan_submissions, dependent: :destroy
  has_many :project_summary_submissions, dependent: :destroy
  has_many :project_summary_approvals, class_name: "ProjectSummarySubmission", foreign_key: :approver_id, dependent: :nullify
  has_many :employee_vertical_mappings, dependent: :destroy
  has_many :mapped_vertical_percents, through: :employee_vertical_mappings, source: :vertical_percent

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
end

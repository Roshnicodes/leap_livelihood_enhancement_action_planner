class BliActivity < ApplicationRecord
  belongs_to :employee

  validates :activity_name, :responsible_user_name, presence: true

  scope :for_vertical, ->(vertical) { where(vertical_name: vertical) if vertical.present? }
  scope :for_project, ->(project) { where(project_name: project) if project.present? }
end

class BliActivity < ApplicationRecord
  belongs_to :employee

  validates :activity_name, :responsible_user_name, presence: true

  scope :current_import, -> { where(import_flag: 0) }
  scope :archived_import, -> { where(import_flag: 1) }
  scope :active, -> { current_import.where(active: true) }
  scope :disabled, -> { current_import.where(active: false) }
  scope :for_vertical, ->(vertical) { where(vertical_name: vertical) if vertical.present? }
  scope :for_project, ->(project) { where(project_name: project) if project.present? }
  # Sheet rows that stash multiple codes in one cell (e.g. "2.2.1, 2.2.2") are not real BLI lines.
  scope :with_single_bli_code, -> {
    where.not(bli_code: [ nil, "" ]).where("bli_code NOT LIKE ?", "%,%")
  }

  def self.single_bli_code?(code)
    value = code.to_s.squish
    value.present? && !value.include?(",")
  end
end

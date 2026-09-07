class ParentActivityAssignment < ApplicationRecord
  belongs_to :employee
  belongs_to :vertical_percent

  validates :source_parent_activity, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :disabled, -> { where(active: false) }
end

class PlanSubmission < ApplicationRecord
  belongs_to :employee
  has_many :plan_submission_items, dependent: :destroy

  validates :mode, :filter_name, presence: true
  validates :original_total, :changed_total, numericality: true
  validate :totals_must_match

  private

  def totals_must_match
    return if (original_total - changed_total).abs < 0.01

    errors.add(:changed_total, "must match original total")
  end
end

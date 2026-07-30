class PlanSubmissionItem < ApplicationRecord
  belongs_to :plan_submission
  belongs_to :bli_activity

  validates :original_fund, :changed_fund, numericality: true
end

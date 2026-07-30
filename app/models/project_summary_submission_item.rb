class ProjectSummarySubmissionItem < ApplicationRecord
  belongs_to :project_summary_submission

  validates :activity_name, :vertical_name, presence: true
  validates :total_amount, :changed_total, *VerticalPercent::MONTH_COLUMNS, numericality: true
  validate :changed_total_must_match_total_amount

  private

  def changed_total_must_match_total_amount
    return if (changed_total - total_amount).abs < 0.01

    errors.add(:changed_total, "must match total amount")
  end
end

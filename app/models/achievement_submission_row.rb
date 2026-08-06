class AchievementSubmissionRow < ApplicationRecord
  belongs_to :achievement_submission
  belongs_to :action_plan_row

  validates :month, inclusion: { in: ActionPlanRow::MONTH_COLUMNS }
end

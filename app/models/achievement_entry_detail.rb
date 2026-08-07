class AchievementEntryDetail < ApplicationRecord
  MAX_FILES = 10
  MAX_FILE_BYTES = 50.megabytes

  belongs_to :action_plan_row
  has_many_attached :files

  validates :month, inclusion: { in: ActionPlanRow::MONTH_COLUMNS }
  validate :files_within_limits

  def self.for_rows(row_ids, month)
    where(action_plan_row_id: row_ids, month: month)
      .includes(files_attachments: :blob)
      .index_by(&:action_plan_row_id)
  end

  def self.find_or_initialize_for!(action_plan_row_id:, month:)
    find_or_initialize_by(action_plan_row_id: action_plan_row_id, month: month)
  end

  private

  def files_within_limits
    return unless files.attached?

    if files.attachments.size > MAX_FILES
      errors.add(:files, "can include at most #{MAX_FILES} files per activity")
    end

    files.each do |file|
      next if file.byte_size.to_i <= MAX_FILE_BYTES

      errors.add(:files, "#{file.filename} exceeds the 50 MB limit")
    end
  end
end

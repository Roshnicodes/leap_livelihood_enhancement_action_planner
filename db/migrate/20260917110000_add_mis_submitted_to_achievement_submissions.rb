class AddMisSubmittedToAchievementSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :achievement_submissions, :mis_submitted, :boolean, default: false, null: false
    add_index :achievement_submissions, [ :mis_submitted, :submitted_at ], name: "idx_achievement_submissions_mis_submitted_time"
  end
end

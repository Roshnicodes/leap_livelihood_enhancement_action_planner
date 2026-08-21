class ActionPlanMonthChange < ApplicationRecord
  MONTH_COLUMNS = ActionPlanRow::MONTH_COLUMNS
  STATUSES = %w[pending approved returned merged].freeze
  ACTIVE_STATUSES = %w[pending approved].freeze
  KEY_ATTRIBUTES = %i[po_id project_name statte user_id to_id asa_theme_id asa_activity_id].freeze

  belongs_to :action_plan_submission, optional: true
  belongs_to :changed_by, class_name: "User", optional: true

  validates :po_id, :project_name, :month, presence: true
  validates :month, inclusion: { in: MONTH_COLUMNS }
  validates :status, inclusion: { in: STATUSES }

  scope :active_overlay, -> { where(status: ACTIVE_STATUSES) }

  def self.capture_active_deltas!(source: "user_edit", status: "pending", changed_by: nil, rows: ActionPlanRow.active_import)
    captured = 0

    rows.find_each do |row|
      captured += capture_row_deltas!(row, source: source, status: status, changed_by: changed_by)
    end

    captured
  end

  def self.capture_row_deltas!(row, source: "user_edit", status: "pending", changed_by: nil, action_plan_submission: nil)
    identity = identity_for(row)
    captured = 0

    MONTH_COLUMNS.each do |month|
      original_value = row.public_send("original_#{month}").to_i
      changed_value = row.public_send(month).to_i
      change = find_by(identity.merge(month: month))

      if changed_value == original_value
        change&.update!(status: "merged", merged_at: Time.current) if change&.status != "merged"
        next
      end

      change ||= new(identity.merge(month: month))
      change.assign_attributes(
        original_value: original_value,
        changed_value: changed_value,
        status: status,
        source: source,
        changed_by: changed_by,
        action_plan_submission: action_plan_submission || change.action_plan_submission
      )
      change.save!
      captured += 1
    end

    captured
  end

  def self.mark_submission_rows!(submission, status:)
    submission.scoped_action_plan_rows.find_each do |row|
      capture_row_deltas!(row, source: "approval", status: status, action_plan_submission: submission)
    end
  end

  def self.apply_active_overlays!
    active_rows_by_key = ActionPlanRow.active_import.to_a.group_by { |row| identity_key_for(row) }
    applied_rows = {}
    applied_cells = 0
    skipped_cells = 0
    merged_cells = 0

    active_overlay.find_each do |change|
      matches = active_rows_by_key[change.identity_key] || []
      if matches.size != 1
        skipped_cells += 1
        next
      end

      row = matches.first
      month = change.month
      imported_baseline = row.public_send("original_#{month}").to_i

      if imported_baseline == change.changed_value.to_i
        change.update!(status: "merged", merged_at: Time.current, last_applied_at: Time.current)
        merged_cells += 1
        next
      end

      row.public_send("#{month}=", change.changed_value.to_i)
      applied_rows[row.id] = row
      change.update!(last_applied_at: Time.current)
      applied_cells += 1
    end

    applied_rows.each_value(&:save!)

    {
      applied_rows: applied_rows.size,
      applied_cells: applied_cells,
      skipped_cells: skipped_cells,
      merged_cells: merged_cells
    }
  end

  def self.identity_for(row)
    {
      po_id: normalized(row.po_id),
      project_name: normalized(row.project_name),
      statte: normalized(row.statte),
      user_id: normalized(row.user_id),
      to_id: normalized(row.to_id),
      asa_theme_id: decimal(row.asa_theme_id),
      asa_activity_id: decimal(row.asa_activity_id)
    }
  end

  def self.identity_key_for(row)
    KEY_ATTRIBUTES.map { |attribute| identity_for(row)[attribute].to_s }
  end

  def identity_key
    KEY_ATTRIBUTES.map { |attribute| public_send(attribute).to_s }
  end

  def self.normalized(value)
    ActionPlanText.normalize(value).to_s
  end

  def self.decimal(value)
    ActionPlanRow.format_decimal_string(normalized(value))
  end
end

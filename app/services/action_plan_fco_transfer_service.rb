require "set"

class ActionPlanFcoTransferService
  class TransferError < StandardError; end

  def initialize(source_fco_id:, target_fco_id:, transferred_by:, note: nil)
    @source_fco_id = ActionPlanFcoTransfer.normalize_fco_id(source_fco_id)
    @target_fco_id = ActionPlanFcoTransfer.normalize_fco_id(target_fco_id)
    @transferred_by = transferred_by
    @note = note.to_s.squish
  end

  def call
    source_fco = find_available_fco!(@source_fco_id, "Source")
    target_fco = find_available_fco!(@target_fco_id, "Target")
    validate_distinct_fcos!
    validate_target_access!

    transfer = ActionPlanFcoTransfer.transaction do
      source_rows = ActionPlanRow.current_import.where(user_id: source_fco[:raw_fco_ids])
      row_ids = source_rows.pluck(:id)
      raise TransferError, "Source FCO has no current action-plan rows to transfer." if row_ids.blank?

      month_changes = ActionPlanMonthChange.active_overlay.where(user_id: source_fco[:raw_fco_ids]).order(:id).to_a
      ensure_month_change_keys_are_available!(month_changes, @target_fco_id)

      transfer = ActionPlanFcoTransfer.create!(
        source_fco_id: @source_fco_id,
        source_fco_name: source_fco[:fco_name],
        target_fco_id: @target_fco_id,
        target_fco_name: target_fco[:fco_name],
        transferred_by: @transferred_by,
        action_plan_row_count: row_ids.size,
        project_count: source_rows.distinct.count(:project_name),
        month_change_count: month_changes.size,
        historical_submission_count: AchievementSubmission.where(fco_id: source_fco[:raw_fco_ids]).count,
        action_plan_row_ids: row_ids,
        month_change_ids: month_changes.map(&:id),
        note: @note.presence
      )

      source_rows.update_all(user_id: @target_fco_id, user_name: target_fco[:fco_name], updated_at: Time.current)
      update_month_change_owner!(month_changes, @target_fco_id)
      transfer
    end

    ActionPlanFcoTransfer.reset_resolution_cache!
    transfer
  end

  def self.revert!(transfer:, reverted_by:)
    new(source_fco_id: transfer.source_fco_id, target_fco_id: transfer.target_fco_id, transferred_by: reverted_by)
      .revert!(transfer: transfer, reverted_by: reverted_by)
  end

  def revert!(transfer:, reverted_by:)
    raise TransferError, "This FCO transfer has already been reverted." unless transfer.active?

    ActionPlanFcoTransfer.transaction do
      source_rows = ActionPlanRow.current_import.where(
        id: Array(transfer.action_plan_row_ids).map(&:to_i),
        user_id: transfer.target_fco_id
      )
      month_changes = ActionPlanMonthChange.active_overlay
        .where(id: Array(transfer.month_change_ids).map(&:to_i), user_id: transfer.target_fco_id)
        .order(:id)
        .to_a

      ensure_month_change_keys_are_available!(month_changes, transfer.source_fco_id)

      source_rows.update_all(
        user_id: transfer.source_fco_id,
        user_name: transfer.source_fco_name,
        updated_at: Time.current
      )
      update_month_change_owner!(month_changes, transfer.source_fco_id)
      transfer.update!(reverted_at: Time.current, reverted_by: reverted_by)
    end

    ActionPlanFcoTransfer.reset_resolution_cache!
    transfer
  end

  private

  def find_available_fco!(fco_id, label)
    ActionPlanFcoTransfer.available_fco(fco_id) ||
      raise(TransferError, "#{label} FCO is not available in the current Action Plan data.")
  end

  def validate_distinct_fcos!
    return unless @source_fco_id == @target_fco_id

    raise TransferError, "Source and target FCO must be different."
  end

  def validate_target_access!
    target_mapping_id = ActionPlanFcoMapping.normalize_fco_id(@target_fco_id)
    return if ActionPlanFcoMapping.active.where(fco_id: target_mapping_id).exists?

    raise TransferError, "Target FCO has no active FCO access mapping. Map the target FCO employee before transferring data."
  end

  def ensure_month_change_keys_are_available!(changes, new_fco_id)
    return if changes.blank?

    target_keys = ActionPlanMonthChange.active_overlay.where(user_id: new_fco_id).each_with_object(Set.new) do |change, keys|
      keys << month_change_key(change, new_fco_id)
    end
    conflicts = changes.select { |change| target_keys.include?(month_change_key(change, new_fco_id)) }
    return if conflicts.blank?

    raise TransferError,
      "#{conflicts.size} active month change#{'s' if conflicts.size > 1} conflicts with the target FCO. Resolve them before transferring."
  end

  def month_change_key(change, fco_id)
    [
      change.po_id,
      change.project_name,
      change.statte,
      fco_id,
      change.to_id,
      change.asa_theme_id,
      change.asa_activity_id,
      change.month
    ].map { |value| value.to_s.squish }.join("\u0000")
  end

  def update_month_change_owner!(changes, fco_id)
    return if changes.blank?

    ActionPlanMonthChange.where(id: changes.map(&:id)).update_all(user_id: fco_id, updated_at: Time.current)
  end
end

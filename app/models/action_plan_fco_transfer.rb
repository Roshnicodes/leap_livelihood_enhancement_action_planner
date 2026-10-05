require "set"

class ActionPlanFcoTransfer < ApplicationRecord
  belongs_to :transferred_by, class_name: "User"
  belongs_to :reverted_by, class_name: "User", optional: true

  scope :active, -> { where(reverted_at: nil) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  validates :source_fco_id, :source_fco_name, :target_fco_id, :target_fco_name, presence: true
  validate :source_and_target_must_differ
  validate :transfer_must_not_create_a_cycle

  before_validation :normalize_fco_details
  after_save :reset_resolution_cache!
  after_destroy :reset_resolution_cache!
  after_rollback :reset_resolution_cache!

  def active?
    reverted_at.blank?
  end

  def reset_resolution_cache!
    self.class.reset_resolution_cache!
  end

  def self.available_fcos
    grouped = Hash.new do |hash, fco_id|
      hash[fco_id] = { fco_id: fco_id, raw_fco_ids: Set.new, names: Hash.new(0), row_count: 0, project_names: Set.new }
    end

    ActionPlanRow.current_import
      .where.not(user_id: [ nil, "" ])
      .pluck(:user_id, :user_name, :project_name)
      .each do |raw_fco_id, raw_fco_name, project_name|
        fco_id = normalize_fco_id(raw_fco_id)
        next if fco_id.blank?

        fco = grouped[fco_id]
        fco[:raw_fco_ids] << raw_fco_id.to_s.squish
        fco[:names][raw_fco_name.to_s.squish] += 1 if raw_fco_name.present?
        fco[:row_count] += 1
        fco[:project_names] << project_name.to_s.squish if project_name.present?
      end

    grouped.values.map do |fco|
      {
        fco_id: fco[:fco_id],
        fco_name: fco[:names].max_by { |name, count| [ count, name ] }&.first || fco[:fco_id],
        raw_fco_ids: fco[:raw_fco_ids].to_a,
        row_count: fco[:row_count],
        project_count: fco[:project_names].size
      }
    end.sort_by { |fco| [ fco[:fco_name].downcase, fco[:fco_id] ] }
  end

  def self.available_fco(fco_id)
    normalized_id = normalize_fco_id(fco_id)
    available_fcos.find { |fco| fco[:fco_id] == normalized_id }
  end

  # Resolve an old physical FCO ID to its active destination. Historical
  # submissions retain their original FCO fields, while reports can still
  # include them under the destination FCO after a transfer.
  def self.target_for(fco_id)
    current_id = normalize_fco_id(fco_id)
    seen_ids = Set.new

    while current_id.present? && !seen_ids.include?(current_id)
      seen_ids << current_id
      destination_id = active_target_map[current_id]
      break if destination_id.blank?

      current_id = destination_id
    end

    current_id
  end

  def self.destination_for(fco_id, fallback_name = nil)
    current_id = normalize_fco_id(fco_id)
    current_name = fallback_name.to_s.squish
    seen_ids = Set.new

    while current_id.present? && !seen_ids.include?(current_id)
      seen_ids << current_id
      transfer = active_transfer_records_by_source[current_id]
      break if transfer.blank?

      current_id = transfer.target_fco_id
      current_name = transfer.target_fco_name
    end

    [ current_id, current_name ]
  end

  def self.source_ids_for(destination_ids)
    destination_ids = Array(destination_ids).filter_map { |fco_id| normalize_fco_id(fco_id) }.uniq
    return [] if destination_ids.blank?

    active_target_map.keys.select do |source_id|
      destination_ids.include?(target_for(source_id))
    end
  end

  def self.reset_resolution_cache!
    @active_target_map = nil
    @active_transfer_records_by_source = nil
  end

  def self.normalize_fco_id(value)
    ActionPlanRow.format_decimal_string(value.to_s.squish)
  end

  def self.active_target_map
    @active_target_map ||= active_transfer_records_by_source.transform_values(&:target_fco_id)
  end

  def self.active_transfer_records_by_source
    @active_transfer_records_by_source ||= active.to_a.index_by(&:source_fco_id)
  end

  private

  def normalize_fco_details
    self.source_fco_id = self.class.normalize_fco_id(source_fco_id)
    self.target_fco_id = self.class.normalize_fco_id(target_fco_id)
    self.source_fco_name = source_fco_name.to_s.squish
    self.target_fco_name = target_fco_name.to_s.squish
  end

  def source_and_target_must_differ
    return if source_fco_id.blank? || target_fco_id.blank?
    return unless source_fco_id == target_fco_id

    errors.add(:target_fco_id, "must be different from source FCO")
  end

  def transfer_must_not_create_a_cycle
    return if source_fco_id.blank? || target_fco_id.blank? || source_fco_id == target_fco_id

    current_id = target_fco_id
    seen_ids = Set.new([ source_fco_id ])
    targets = self.class.active_target_map.except(source_fco_id)

    while current_id.present?
      if seen_ids.include?(current_id)
        errors.add(:target_fco_id, "would create a circular FCO transfer")
        return
      end

      seen_ids << current_id
      current_id = targets[current_id]
    end
  end
end

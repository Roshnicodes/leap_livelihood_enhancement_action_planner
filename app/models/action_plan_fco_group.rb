class ActionPlanFcoGroup
  GROUPS = {
    "16" => { ids: %w[16 17], name: "Jobat - FCO" },
    "14" => { ids: %w[14 11], name: "Bhawanipatna - FCO" },
    # Sidhi (12) is a separate FCO.  It used to be included in Mandla's
    # legacy group, which meant selecting Mandla also selected Sidhi rows and
    # caused their targets/achievements to appear under the wrong FCO.
    "15" => { ids: %w[15], name: "Mandla - FCO" },
    "18" => { ids: %w[18], name: "Jamtara - FCO" },
    "19" => { ids: %w[19], name: "Pakur - FCO" },
    "28" => { ids: %w[28], name: "Financial Inclusion" }
  }.freeze

  ID_TO_GROUP = GROUPS.each_with_object({}) do |(canonical_id, group), lookup|
    group[:ids].each { |id| lookup[id] = canonical_id }
  end.freeze

  def self.canonical_id(fco_id)
    physical_id = transferred_target_id(normalize_id(fco_id))
    ID_TO_GROUP.fetch(physical_id, physical_id)
  end

  def self.ids_for(fco_id)
    id = canonical_id(fco_id)
    physical_ids = GROUPS.fetch(id, { ids: [ id ] })[:ids]
    (physical_ids + transferred_source_ids(physical_ids)).uniq
  end

  def self.name_for(fco_id, fallback_name = nil)
    GROUPS.dig(canonical_id(fco_id), :name) || fallback_name.to_s.squish
  end

  def self.display_id_for(fco_id)
    ids_for(fco_id).join(",")
  end

  def self.group_options(options)
    grouped = {}

    options.each do |label, value|
      id = normalize_id(value)
      canonical = canonical_id(id)
      grouped[canonical] ||= [ name_for(canonical, label), display_id_for(canonical) ]
    end

    grouped.values.sort_by(&:first)
  end

  def self.normalize_id(value)
    ActionPlanRow.format_decimal_string(value.to_s.squish)
  end

  def self.transferred_target_id(fco_id)
    ActionPlanFcoTransfer.target_for(fco_id)
  rescue ActiveRecord::StatementInvalid
    # Allows a zero-downtime deploy where application code is loaded just before
    # the FCO transfer migration has been applied.
    fco_id
  end

  def self.transferred_source_ids(fco_ids)
    ActionPlanFcoTransfer.source_ids_for(fco_ids)
  rescue ActiveRecord::StatementInvalid
    []
  end
end

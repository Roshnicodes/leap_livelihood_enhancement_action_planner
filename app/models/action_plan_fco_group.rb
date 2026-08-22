class ActionPlanFcoGroup
  GROUPS = {
    "16" => { ids: %w[16 17], name: "Jobat - FCO" },
    "14" => { ids: %w[14 11], name: "Bhawanipatna - FCO" },
    "15" => { ids: %w[15 12], name: "Mandla - FCO" }
  }.freeze

  ID_TO_GROUP = GROUPS.each_with_object({}) do |(canonical_id, group), lookup|
    group[:ids].each { |id| lookup[id] = canonical_id }
  end.freeze

  def self.canonical_id(fco_id)
    ID_TO_GROUP.fetch(normalize_id(fco_id), normalize_id(fco_id))
  end

  def self.ids_for(fco_id)
    id = canonical_id(fco_id)
    GROUPS.fetch(id, { ids: [ id ] })[:ids]
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
end

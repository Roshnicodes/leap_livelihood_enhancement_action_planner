# The FY 2026-27 source file was saved with text like "Land &amp;amp; Water ..."
# and then split on ";", so each "&amp;" pushed the rest of the row one or more
# cells to the right: "Land &amp" | "amp" | "Water Resources ..." landed in
# Project Theme / Project Activity ID / Project Activity, and the real Unit_Type
# and A_remark fell off the end. This joins the pieces back together and fills
# the cells that were lost from the last clean source file. Only the text
# columns between Project Theme and A_remark are touched; FCO/TO, month targets
# and achievements stay exactly as they are.
class ActionPlanSplitEntityRepair
  SHIFTED_COLUMNS = %i[theme activity_id activity unit_type a_remark].freeze
  SPLIT_ENTITY = /&amp\z/

  # Values lost from the end of the shifted rows, taken from the 2026-08-11
  # action plan file (the last upload before the text was split).
  LOST_VALUES = {
    [ "Walmart Foundation-2", "3", "3.6" ] => { unit_type: "No" },
    **%w[5.1 5.101 5.2 5.3 5.4 5.5 5.6 5.7 5.8 5.9].to_h { |id| [ [ "Walmart Foundation-2", "5", id ], { unit_type: "No" } ] },
    [ "Walmart Foundation-2", "5", "5.2" ] => { unit_type: "No", activity: "Construction & Rennovation of Stop Dam" },
    [ "Walmart Foundation-2", "6", "6.1" ] => { unit_type: "Ha" },
    [ "Walmart Foundation-2", "6", "6.101" ] => { unit_type: "Mln Ltr" },
    [ "Walmart Foundation-2", "6", "6.11" ] => { unit_type: "Rs. Lakh" },
    **%w[6.2 6.3 6.4 6.5 6.7].to_h { |id| [ [ "Walmart Foundation-2", "6", id ], { unit_type: "No" } ] },
    [ "Walmart Foundation-2", "6", "6.6" ] => { unit_type: "No", activity: "Construction & Renovation of Earthen Dams/ Stop Dam Tank De-siltation" },
    [ "Walmart Foundation-2", "6", "6.8" ] => { unit_type: "No." },
    [ "Walmart Foundation-2", "6", "6.9" ] => { unit_type: "Acre" }
  }.freeze

  def self.affected_rows
    ActionPlanRow.where(
      SHIFTED_COLUMNS.first(4).map { |column| ActionPlanRow.arel_table[column].matches("%&amp") }.reduce(:or)
    )
  end

  def self.repaired_attributes(row)
    pieces = SHIFTED_COLUMNS.map { |column| row.public_send(column) }
    joined = join_split_pieces(pieces)
    return if joined.size == pieces.size

    attributes = SHIFTED_COLUMNS.zip(joined).to_h
    lost = LOST_VALUES.fetch([ row.project_name, row.theme_id.to_s, attributes[:activity_id].to_s ], {})
    attributes[:activity] = lost[:activity] if lost[:activity] && attributes[:activity].to_s.match?(SPLIT_ENTITY)
    attributes[:unit_type] ||= lost[:unit_type]
    attributes
  end

  def self.join_split_pieces(pieces)
    pieces.each_with_object([]) do |piece, joined|
      previous = joined.last
      if previous.to_s.match?(SPLIT_ENTITY)
        next if piece == "amp"

        separator = previous.to_s.match?(/\s&amp\z/) ? " " : ""
        joined[-1] = "#{previous.sub(SPLIT_ENTITY, "&")}#{separator}#{piece}"
      else
        joined << piece
      end
    end
  end

  def self.call(apply: false)
    changes = affected_rows.find_each.filter_map do |row|
      attributes = repaired_attributes(row)
      next unless attributes

      row.update_columns(attributes) if apply
      [ row, attributes ]
    end

    changes
  end
end

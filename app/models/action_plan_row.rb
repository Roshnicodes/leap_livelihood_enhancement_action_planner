class ActionPlanRow < ApplicationRecord
  has_many :achievement_entry_details, dependent: :destroy

  WITHOUT_FCO_FILTER_VALUE = "__without_fco__".freeze
  WITHOUT_TO_FILTER_VALUE = "__without_to__".freeze
  MONTH_COLUMNS = %w[apr may jun jul aug sep oct nov dec jan feb mar].freeze
  ORIGINAL_MONTH_COLUMNS = MONTH_COLUMNS.map { |month| "original_#{month}" }.freeze
  TARGET_MONTH_COLUMNS = MONTH_COLUMNS.map { |month| "#{month}_t" }.freeze
  MONTH_DISPLAY_PAIRS = MONTH_COLUMNS.zip(TARGET_MONTH_COLUMNS).map do |month, achievement_month|
    label = month.capitalize
    {
      target_column: month,
      achievement_column: achievement_month,
      month_label: label,
      target_label: "#{label} Target",
      achievement_label: "#{label} Achievement"
    }
  end.freeze
  ADMIN_ONLY_COLUMNS = [
    { header: "State", attribute: :statte },
    { header: "Project_Owner", attribute: :project_owner }
  ].freeze
  PO_ID_COLUMN = { header: "PO_ID", attribute: :po_id }.freeze
  PROJECT_ID_COLUMN = { header: "Project_ID", attribute: :project_id }.freeze
  USER_PROJECT_COLUMNS = [
    { header: "Project", attribute: :project_name }
  ].freeze
  ADMIN_PROJECT_COLUMNS = [
    { header: "Project", attribute: :project_name }
  ].freeze
  SHARED_DETAIL_COLUMNS = [
    { header: "FCO ID", attribute: :user_id },
    { header: "FCO Name", attribute: :user_name },
    { header: "TO_ID", attribute: :to_id },
    { header: "TO_NAME", attribute: :to_name },
    { header: "ASA_Theme_ID", attribute: :asa_theme_id },
    { header: "ASA_Theme", attribute: :asa_theme },
    { header: "ASA_Activity_ID", attribute: :asa_activity_id },
    { header: "ASA_Activity_Name", attribute: :asa_activity_name },
    { header: "Project Theme ID", attribute: :theme_id },
    { header: "Project Theme", attribute: :theme },
    { header: "Project Activity ID", attribute: :activity_id },
    { header: "Project Activity", attribute: :activity },
    { header: "Unit_Type", attribute: :unit_type }
  ].freeze
  ADMIN_DETAIL_COLUMNS = [
    { header: "A_remark", attribute: :a_remark }
  ].freeze
  FCO_COLUMN_ATTRIBUTES = %i[user_id user_name].freeze
  TO_COLUMN_ATTRIBUTES = %i[to_id to_name].freeze
  DISPLAY_GROUP_ATTRIBUTES = [
    :po_id,
    :project_id,
    :statte,
    :project_owner,
    :project_name,
    :user_id,
    :user_name,
    :to_id,
    :to_name,
    :asa_theme_id,
    :asa_theme,
    :asa_activity_id,
    :asa_activity_name,
    :theme_id,
    :theme,
    :activity_id,
    :activity,
    :unit_type,
    :a_remark
  ].freeze
  DISPLAY_SUM_ATTRIBUTES = [
    *MONTH_COLUMNS.map(&:to_sym),
    *ORIGINAL_MONTH_COLUMNS.map(&:to_sym),
    *TARGET_MONTH_COLUMNS.map(&:to_sym),
    :planned_total
  ].freeze
  PILL_ATTRIBUTES = %i[id_new po_id project_id user_id to_id theme_id activity_id asa_theme_id asa_activity_id].freeze
  DECIMAL_ATTRIBUTES = %i[activity_id].freeze
  MONTH_TOTAL_COLUMNS = [
    { header: "Total Target", total_method: :monthly_total },
    { header: "Total Achievement", total_method: :target_total }
  ].freeze

  def self.display_columns(admin: false, without_fco: false, without_to: false)
    columns = if admin
      [ PROJECT_ID_COLUMN, *ADMIN_ONLY_COLUMNS, *ADMIN_PROJECT_COLUMNS, *SHARED_DETAIL_COLUMNS, *ADMIN_DETAIL_COLUMNS ]
    else
      [ PROJECT_ID_COLUMN, *USER_PROJECT_COLUMNS, *SHARED_DETAIL_COLUMNS ]
    end

    columns.reject do |column|
      (without_fco && FCO_COLUMN_ATTRIBUTES.include?(column[:attribute])) ||
        (without_to && TO_COLUMN_ATTRIBUTES.include?(column[:attribute]))
    end
  end

  EXPORT_COLUMNS = [
    PO_ID_COLUMN,
    *display_columns(admin: true),
    *MONTH_DISPLAY_PAIRS.flat_map do |pair|
      [
        { header: pair[:target_label], attribute: pair[:target_column].to_sym },
        { header: pair[:achievement_label], attribute: pair[:achievement_column].to_sym }
      ]
    end,
    *MONTH_TOTAL_COLUMNS.map { |column| { header: column[:header], total_method: column[:total_method] } }
  ].freeze

  MONTH_SUM_SQL = MONTH_COLUMNS.map { |month| "COALESCE(#{month}, 0)" }.join(" + ").freeze

  scope :current_import, -> { where(import_flag: 0) }
  scope :active_import, -> { current_import.where(active: true) }
  scope :disabled_import, -> { current_import.where(active: false) }
  scope :unbalanced, -> { where("(#{MONTH_SUM_SQL}) <> planned_total") }
  scope :matching_verticals, lambda { |vertical_names|
    names = Array(vertical_names).flat_map { |name| vertical_match_tokens(name) }.uniq.compact_blank
    return all if names.empty?

    where(names.map { |token| matching_vertical_clause(token) }.reduce(:or))
  }
  scope :matching_action_plan_vertical_mappings, lambda { |mappings|
    pairs = Array(mappings).map { |mapping| [ mapping.state_code, mapping.asa_theme_id ] }.uniq
    return none if pairs.empty?

    where(pairs.map { |state_code, asa_theme_id| matching_action_plan_vertical_clause(state_code, asa_theme_id) }.reduce(:or))
  }

  def self.format_decimal_string(raw)
    text = raw.to_s.squish
    return text if text.blank?
    return text unless text.match?(/\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/)

    BigDecimal(text).round(10).to_s("F").sub(/\.?0+\z/, "")
  rescue ArgumentError
    text
  end

  def self.grouped_for_display(rows, without_fco: false, without_to: false)
    return rows unless without_fco || without_to

    rows.to_a.group_by do |row|
      display_group_attributes(without_fco: without_fco, without_to: without_to).map do |attribute|
        display_group_value(row.public_send(attribute), attribute)
      end
    end.values.map do |group|
      display_group_row(group, without_fco: without_fco, without_to: without_to)
    end
  end

  def self.display_group_attributes(without_fco:, without_to:)
    DISPLAY_GROUP_ATTRIBUTES.reject do |attribute|
      (without_fco && FCO_COLUMN_ATTRIBUTES.include?(attribute)) ||
        (without_to && TO_COLUMN_ATTRIBUTES.include?(attribute))
    end
  end

  def self.display_group_value(value, attribute)
    if DECIMAL_ATTRIBUTES.include?(attribute)
      format_decimal_string(value)
    else
      ActionPlanText.group_key(value)
    end
  end

  def self.display_group_row(group, without_fco:, without_to:)
    row = group.first.dup

    FCO_COLUMN_ATTRIBUTES.each { |attribute| row.public_send("#{attribute}=", nil) } if without_fco
    TO_COLUMN_ATTRIBUTES.each { |attribute| row.public_send("#{attribute}=", nil) } if without_to

    DISPLAY_SUM_ATTRIBUTES.each do |attribute|
      row.public_send("#{attribute}=", group.sum { |item| item.public_send(attribute) || 0 })
    end

    row
  end

  before_save :normalize_formatted_codes

  def normalize_formatted_codes
    self.activity_id = self.class.format_decimal_string(activity_id) if activity_id.present?
  end

  validates :po_id, :project_name, presence: true

  def self.vertical_match_tokens(vertical_name)
    name = vertical_name.to_s.squish
    tokens = [ name ]
    suffix = name.split(/\s*-\s*/).last
    tokens << suffix if suffix.present? && suffix != name

    if name.match?(/wrd|water resource development/i)
      tokens += [
        "Water Resource Development",
        "WRD",
        "Dugwell",
        "Dug-well",
        "Borewell",
        "Bore well",
        "Stop Dam",
        "Solar LIS"
      ]
    end

    if name.match?(/livestock/i)
      tokens << "Livestock"
    end

    if name.match?(/agriculture|agro|sustainable agriculture/i)
      tokens += [ "Agriculture", "Agro", "Agri", "Horti", "Farming" ]
    end

    if name.match?(/financial inclusion/i)
      tokens += [ "Financial Inclusion", "Financial" ]
    end

    tokens.map(&:squish).uniq.compact_blank
  end

  def self.matching_vertical_clause(token)
    sanitized = sanitize_sql_like(token.to_s.downcase)
    arel_table[:theme].lower.matches("%#{sanitized}%")
      .or(arel_table[:asa_theme].lower.matches("%#{sanitized}%"))
      .or(arel_table[:activity].lower.matches("%#{sanitized}%"))
  end

  def self.matching_action_plan_vertical_clause(state_code, asa_theme_id)
    arel_table[:statte].eq(state_code.to_s.squish.upcase)
      .and(arel_table[:asa_theme_id].eq(format_decimal_string(asa_theme_id)))
  end

  def self.normalize_vertical_key(name)
    name.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end

  def monthly_total
    MONTH_COLUMNS.sum { |month| public_send(month).to_i }
  end

  def target_total
    TARGET_MONTH_COLUMNS.sum { |month| public_send(month).to_d }
  end

  # Month-wise targets may be redistributed, but they must always add up to the
  # planned annual total captured at import time.
  def target_variance
    monthly_total - planned_total.to_i
  end

  def balanced?
    target_variance.zero?
  end
end

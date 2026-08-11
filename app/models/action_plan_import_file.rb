require "fileutils"
require "securerandom"

class ActionPlanImportFile < ApplicationRecord
  IMPORT_TYPES = {
    "project_owner" => "Project owner file",
    "action_plan" => "Project BLI mapping file",
    "vertical_mapping" => "User vertical mapping file",
    "before_import_snapshot" => "Before import snapshot"
  }.freeze
  STATUSES = %w[saved imported failed backup].freeze

  belongs_to :uploaded_by, class_name: "User", optional: true

  validates :import_type, inclusion: { in: IMPORT_TYPES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :original_filename, :storage_path, :imported_at, :financial_year, presence: true
  validates :financial_year, format: { with: /\A\d{4}-\d{4}\z/ }

  before_validation :assign_financial_year

  scope :recent, -> { order(imported_at: :desc, id: :desc) }
  scope :for_financial_year, ->(year) { where(financial_year: year) if year.present? }

  def self.financial_year_for(time = Time.current)
    date = time.in_time_zone.to_date
    start_year = date.month >= 4 ? date.year : date.year - 1
    "#{start_year}-#{start_year + 1}"
  end

  def self.financial_year_folder_for(financial_year)
    "fy_#{financial_year.to_s.tr("-", "_")}"
  end

  def self.capture!(upload:, import_type:, uploaded_by:)
    original_filename = upload.original_filename.to_s.squish.presence || "uploaded_file"
    extension = File.extname(original_filename).presence || ".dat"
    imported_at = Time.current
    financial_year = financial_year_for(imported_at)
    stored_name = "#{imported_at.strftime("%Y%m%d_%H%M%S")}_#{SecureRandom.hex(8)}#{extension.downcase}"
    relative_path = File.join("storage", "action_plan_imports", financial_year_folder_for(financial_year), import_type, stored_name)
    absolute_path = Rails.root.join(relative_path)

    FileUtils.mkdir_p(File.dirname(absolute_path))
    FileUtils.cp(upload.path, absolute_path)

    create!(
      import_type: import_type,
      original_filename: original_filename,
      content_type: upload.respond_to?(:content_type) ? upload.content_type : nil,
      byte_size: upload.respond_to?(:size) ? upload.size.to_i : File.size(absolute_path),
      storage_path: relative_path,
      uploaded_by: uploaded_by,
      financial_year: financial_year,
      imported_at: imported_at
    )
  end

  def self.capture_active_snapshot!(uploaded_by:)
    rows = ActionPlanRow.active_import.order(:id)
    return unless rows.exists?

    imported_at = Time.current
    financial_year = financial_year_for(imported_at)
    capture_rows_snapshot!(
      rows: rows,
      filename: "action_plan_before_import_#{financial_year}_#{imported_at.strftime("%Y%m%d_%H%M%S")}.csv",
      uploaded_by: uploaded_by,
      imported_at: imported_at
    )
  end

  def self.capture_rows_snapshot!(rows:, filename:, uploaded_by: nil, imported_at: Time.current)
    rows = rows.order(:id) if rows.respond_to?(:order)
    financial_year = financial_year_for(imported_at)
    relative_path = File.join("storage", "action_plan_imports", financial_year_folder_for(financial_year), "before_import_snapshot", "#{SecureRandom.hex(8)}_#{filename}")
    absolute_path = Rails.root.join(relative_path)

    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.binwrite(absolute_path, ActionPlanExporter.new(rows).csv)

    create!(
      import_type: "before_import_snapshot",
      original_filename: filename,
      content_type: "text/csv; charset=utf-8",
      byte_size: File.size(absolute_path),
      storage_path: relative_path,
      uploaded_by: uploaded_by,
      row_count: rows.count,
      status: "backup",
      financial_year: financial_year,
      imported_at: imported_at
    )
  end

  def type_label
    IMPORT_TYPES.fetch(import_type, import_type.to_s.titleize)
  end

  def absolute_path
    Rails.root.join(storage_path)
  end

  def file_available?
    File.file?(absolute_path)
  end

  def mark_imported!(row_count)
    update!(status: "imported", row_count: row_count, error_message: nil)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message.to_s.truncate(500))
  end

  private

  def assign_financial_year
    self.financial_year = self.class.financial_year_for(imported_at || Time.current) if financial_year.blank?
  end
end

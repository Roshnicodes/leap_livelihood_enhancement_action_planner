require "fileutils"
require "securerandom"

class PbImportFile < ApplicationRecord
  STATUSES = %w[pending imported failed backup].freeze
  FILE_KINDS = %w[source parent_activity_mapping before_import_snapshot].freeze

  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :file_kind, inclusion: { in: FILE_KINDS }
  validates :original_filename, :storage_path, :imported_at, :financial_year, presence: true
  validates :financial_year, format: { with: /\A\d{4}-\d{4}\z/ }

  before_validation :assign_financial_year

  scope :recent, -> { order(imported_at: :desc, id: :desc) }
  scope :imported, -> { where(status: "imported") }
  scope :pending, -> { where(status: "pending") }
  scope :for_financial_year, ->(year) { where(financial_year: year) if year.present? }

  def self.financial_year_for(time = Time.current)
    date = time.in_time_zone.to_date
    start_year = date.month >= 4 ? date.year : date.year - 1
    "#{start_year}-#{start_year + 1}"
  end

  def self.financial_year_folder_for(financial_year)
    "fy_#{financial_year.to_s.tr("-", "_")}"
  end

  def self.latest_source
    where(status: "imported", file_kind: "source").recent.first
  end

  def self.ensure_latest_source!
    latest_source || capture_default_source!
  end

  def self.capture_default_source!
    source_path = if File.exist?(BliActivitySync::DEFAULT_XLSX_PATH)
      BliActivitySync::DEFAULT_XLSX_PATH
    elsif File.exist?(BliActivitySync::DEFAULT_CSV_PATH)
      BliActivitySync::DEFAULT_CSV_PATH
    end
    return if source_path.blank?

    capture_path!(
      path: source_path,
      original_filename: File.basename(source_path),
      content_type: File.extname(source_path).downcase == ".csv" ? "text/csv" : PbActivityExporter::XLSX_CONTENT_TYPE,
      status: "imported",
      file_kind: "source",
      row_count: BliActivity.count
    )
  end

  def self.capture!(upload:, uploaded_by:, file_kind: "source")
    capture_path!(
      path: upload.path,
      original_filename: upload.original_filename,
      content_type: upload.respond_to?(:content_type) ? upload.content_type : nil,
      byte_size: upload.respond_to?(:size) ? upload.size.to_i : nil,
      uploaded_by: uploaded_by,
      status: "pending",
      file_kind: file_kind
    )
  end

  def self.capture_path!(path:, original_filename: nil, content_type: nil, byte_size: nil, uploaded_by: nil, status: "pending", file_kind: "source", row_count: nil, imported_at: Time.current)
    original_filename = original_filename.to_s.squish.presence || File.basename(path)
    extension = File.extname(original_filename).presence || ".dat"
    financial_year = financial_year_for(imported_at)
    stored_name = "#{imported_at.strftime("%Y%m%d_%H%M%S")}_#{SecureRandom.hex(8)}#{extension.downcase}"
    relative_path = File.join("storage", "pb_imports", financial_year_folder_for(financial_year), file_kind, stored_name)
    absolute_path = Rails.root.join(relative_path)

    FileUtils.mkdir_p(File.dirname(absolute_path))
    FileUtils.cp(path, absolute_path)

    create!(
      original_filename: original_filename,
      content_type: content_type,
      byte_size: byte_size || File.size(absolute_path),
      storage_path: relative_path,
      uploaded_by: uploaded_by,
      status: status,
      file_kind: file_kind,
      financial_year: financial_year,
      row_count: row_count,
      imported_at: imported_at
    )
  end

  def self.capture_active_snapshot!(uploaded_by: nil)
    source_file = latest_source
    return capture_source_snapshot!(source_file, uploaded_by: uploaded_by) if source_file&.file_available?
    return unless BliActivity.exists?

    imported_at = Time.current
    financial_year = financial_year_for(imported_at)
    stored_name = "pb_active_before_#{financial_year}_#{imported_at.strftime("%Y%m%d_%H%M%S")}.xlsx"
    relative_path = File.join("storage", "pb_imports", financial_year_folder_for(financial_year), "before_import_snapshot", stored_name)
    absolute_path = Rails.root.join(relative_path)

    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.binwrite(absolute_path, PbActivityExporter.active_xlsx)

    create!(
      original_filename: stored_name,
      content_type: PbActivityExporter::XLSX_CONTENT_TYPE,
      byte_size: File.size(absolute_path),
      storage_path: relative_path,
      uploaded_by: uploaded_by,
      row_count: BliActivity.count,
      status: "backup",
      file_kind: "before_import_snapshot",
      financial_year: financial_year,
      imported_at: imported_at
    )
  end

  def self.capture_source_snapshot!(source_file, uploaded_by: nil)
    imported_at = Time.current
    financial_year = financial_year_for(imported_at)
    capture_path!(
      path: source_file.absolute_path,
      original_filename: "pb_before_import_#{financial_year}_#{imported_at.strftime("%Y%m%d_%H%M%S")}_#{source_file.original_filename}",
      content_type: source_file.content_type,
      byte_size: source_file.byte_size,
      uploaded_by: uploaded_by,
      status: "backup",
      file_kind: "before_import_snapshot",
      row_count: source_file.row_count,
      imported_at: imported_at
    )
  end

  def absolute_path
    Rails.root.join(storage_path)
  end

  def file_available?
    File.file?(absolute_path)
  end

  def mark_imported!(row_count)
    update!(status: "imported", row_count: row_count, error_message: nil, approved_at: Time.current)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message.to_s.truncate(500))
  end

  def approve!(approver:)
    row_count = BliActivitySync.new(source_path: absolute_path.to_s, save_history: false).call
    update!(
      status: "imported",
      row_count: row_count,
      error_message: nil,
      approved_by: approver,
      approved_at: Time.current
    )
  rescue Zip::Error, CSV::MalformedCSVError, ActiveRecord::ActiveRecordError => error
    mark_failed!(error.message)
    raise
  end

  private

  def assign_financial_year
    self.financial_year = self.class.financial_year_for(imported_at || Time.current) if financial_year.blank?
  end
end

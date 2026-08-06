require "fileutils"
require "securerandom"

class ActionPlanImportFile < ApplicationRecord
  IMPORT_TYPES = {
    "project_owner" => "Project owner file",
    "action_plan" => "Project BLI mapping file",
    "vertical_mapping" => "User vertical mapping file"
  }.freeze
  STATUSES = %w[saved imported failed].freeze

  belongs_to :uploaded_by, class_name: "User", optional: true

  validates :import_type, inclusion: { in: IMPORT_TYPES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :original_filename, :storage_path, :imported_at, presence: true

  scope :recent, -> { order(imported_at: :desc, id: :desc) }

  def self.capture!(upload:, import_type:, uploaded_by:)
    original_filename = upload.original_filename.to_s.squish.presence || "uploaded_file"
    extension = File.extname(original_filename).presence || ".dat"
    imported_at = Time.current
    stored_name = "#{imported_at.strftime("%Y%m%d_%H%M%S")}_#{SecureRandom.hex(8)}#{extension.downcase}"
    relative_path = File.join("storage", "action_plan_imports", import_type, stored_name)
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
end

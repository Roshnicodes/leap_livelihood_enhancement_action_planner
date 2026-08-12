class DonorReportUpload < ApplicationRecord
  FREQUENCIES = [
    "Monthly",
    "Quarterly",
    "Half Yearly",
    "Annual"
  ].freeze

  belongs_to :donor_report_type
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :document_file
  has_one_attached :screenshot_file
  has_one_attached :file

  validates :project_name, :frequency, :submission_date, presence: true
  validates :frequency, inclusion: { in: FREQUENCIES }
  validate :document_file_must_be_attached
  validate :screenshot_file_must_be_attached

  scope :recent, -> { includes(:donor_report_type, :uploaded_by).order(created_at: :desc, id: :desc) }
  scope :for_project, ->(project_name) { where(project_name: project_name) if project_name.present? }
  scope :for_frequency, ->(frequency) { where(frequency: frequency) if frequency.present? }
  scope :for_report_type, ->(report_type_id) { where(donor_report_type_id: report_type_id) if report_type_id.present? }

  def file_size
    document_file.attached? ? document_file.blob.byte_size : 0
  end

  def file_name
    document_file.attached? ? document_file.filename.to_s : "-"
  end

  def screenshot_file_name
    screenshot_file.attached? ? screenshot_file.filename.to_s : "-"
  end

  private

  def document_file_must_be_attached
    errors.add(:document_file, "must be attached") unless document_file.attached?
  end

  def screenshot_file_must_be_attached
    errors.add(:screenshot_file, "must be attached") unless screenshot_file.attached?
  end
end

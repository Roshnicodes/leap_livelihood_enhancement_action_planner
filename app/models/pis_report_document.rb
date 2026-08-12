class PisReportDocument < ApplicationRecord
  belongs_to :pis_document_type
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :file

  validates :project_name, :financial_year, :submission_date, presence: true
  validates :financial_year, format: { with: /\A\d{4}-\d{4}\z/ }
  validate :file_must_be_attached

  scope :recent, -> { includes(:pis_document_type, :uploaded_by).order(created_at: :desc, id: :desc) }
  scope :for_project, ->(project_name) { where(project_name: project_name) if project_name.present? }
  scope :for_financial_year, ->(financial_year) { where(financial_year: financial_year) if financial_year.present? }
  scope :for_document_type, ->(document_type_id) { where(pis_document_type_id: document_type_id) if document_type_id.present? }

  def self.financial_year_for(date = Date.current)
    date = date.to_date
    start_year = date.month >= 4 ? date.year : date.year - 1
    "#{start_year}-#{start_year + 1}"
  end

  def file_size
    file.attached? ? file.blob.byte_size : 0
  end

  def file_name
    file.attached? ? file.filename.to_s : "-"
  end

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end

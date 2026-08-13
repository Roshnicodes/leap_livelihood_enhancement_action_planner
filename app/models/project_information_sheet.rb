class ProjectInformationSheet < ApplicationRecord
  HEADER_LABELS = [
    "Project ID",
    "Project Title",
    "Donor",
    "Category",
    "Project Period",
    *ReportFinancialYear.options.reverse.map { |year| ReportFinancialYear.short_label(year) },
    "Total",
    "Project Location",
    "Project Area Map",
    "Donor Reporting Officer",
    "Start Date",
    "End Date",
    "Project Objectives",
    "No. of HH To be Covered",
    "FCO Name",
    "PO",
    "Reporting System",
    "Physical",
    "Financial",
    "Annexure"
  ].freeze

  belongs_to :uploaded_by, class_name: "User", optional: true

  validates :project_id, presence: true, uniqueness: true

  scope :recent, -> { order(updated_at: :desc, id: :desc) }
  scope :by_project_id, -> { order(Arel.sql("NULLIF(regexp_replace(project_id, '[^0-9]', '', 'g'), '')::integer ASC NULLS LAST"), :project_id) }
  scope :for_project, lambda { |project|
    if project.present?
      where("project_title = :project OR project_id = :project", project: project)
    end
  }
  scope :with_financial_year, lambda { |financial_year|
    normalized_year = ReportFinancialYear.normalize(financial_year)
    if normalized_year.present?
      where("(yearly_amounts ->> :year)::numeric <> 0", year: normalized_year)
    end
  }

  def self.financial_year_options
    saved = distinct.pluck(:yearly_amounts).flat_map { |amounts| amounts.to_h.keys }
    (ReportFinancialYear.options + saved).compact_blank.uniq.sort.reverse
  end

  def amount_for(financial_year)
    yearly_amounts.to_h[ReportFinancialYear.normalize(financial_year).to_s]
  end

  def amount_present_for?(financial_year)
    BigDecimal(amount_for(financial_year).to_s.presence || "0").nonzero?
  end

  def project_option_label
    project_title.presence || project_id
  end
end

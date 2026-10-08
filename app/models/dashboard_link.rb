require "uri"

class DashboardLink < ApplicationRecord
  PHN_DASHBOARD_KEY = "phn_dashboard".freeze
  DEFAULT_PNB_DASHBOARD_URL = "https://app.powerbi.com/view?r=eyJrIjoiYTUzNTY2ODYtMmYxNS00MDlmLTg1YzMtMmM3OTJkNGRlN2UyIiwidCI6ImQzODExMjIyLTI4MDItNDIzOC1hOTY3LTM2ZjQyODg4NGU1NiJ9&pageName=fc960431fa40bbffdefb".freeze

  belongs_to :updated_by, class_name: "User", optional: true

  validates :key, :url, presence: true
  validates :key, uniqueness: true
  validate :url_must_be_http_or_https

  before_validation :normalize_url

  # The existing key remains unchanged so a deployed PHN link is preserved
  # while the user-facing dashboard has been renamed to PNB.
  def self.pnb_dashboard
    find_or_create_by!(key: PHN_DASHBOARD_KEY) do |dashboard_link|
      dashboard_link.url = DEFAULT_PNB_DASHBOARD_URL
    end
  end

  private

  def normalize_url
    self.url = url.to_s.strip
  end

  def url_must_be_http_or_https
    uri = URI.parse(url.to_s)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:url, "must be a valid http or https URL")
  rescue URI::InvalidURIError
    errors.add(:url, "must be a valid http or https URL")
  end
end

require "json"
require "net/http"
require "uri"

# Sends an email for every approval event (submit, approve at each level,
# return) through krai, the same way Apurti sends its notification mails; the
# server has no SMTP:
#
#   GET https://krai.asaindia.org/<page>?to_email=...&to_name=...&subject=...&message=...&link=...
#
# LEAP_MAIL_RELAY_URL is krai's address (https://krai.asaindia.org/) or a full
# page address (…/x.aspx). Without a page in the URL, mails go to DEFAULT_PAGE.
#
# Off until LEAP_MAIL_RELAY_URL is set, so nothing changes before krai has a
# page for LEAP. A failed mail never affects the submission or approval.
class LeapMailRelay
  class DeliveryError < StandardError; end

  FIELDS = %w[to_email to_name subject message link].freeze
  DEFAULT_PAGE = "leap_nnotify.aspx".freeze
  DEFAULT_APP_URL = "https://ationplan.asaindia.org".freeze
  KRAI_SENT = /email sent successfully/i
  KRAI_REFUSED = /invalid|missing|not sent|failed|error/i
  TIMEOUT_SECONDS = 15
  MAX_REDIRECTS = 3

  def self.url
    ENV["LEAP_MAIL_RELAY_URL"].to_s.strip
  end

  def self.enabled?
    url.present?
  end

  # Queues one mail; never raises, so callers can fire and forget.
  def self.notify(kind, recipient:, subject:, message:, path:)
    return false unless enabled?

    email = recipient&.email.to_s.strip
    return false unless email.include?("@")

    params = {
      "to_email" => email,
      "to_name" => recipient.name.presence || email,
      "subject" => subject.to_s.squish,
      "message" => message.to_s.squish,
      "link" => link_for(path)
    }
    LeapMailJob.perform_later(kind.to_s, params)
    true
  rescue StandardError => error
    Rails.logger.error("LeapMailRelay could not queue kind=#{kind}: #{error.class} #{error.message}")
    false
  end

  def self.link_for(path)
    "#{(ENV["LEAP_MAIL_APP_URL"].presence || DEFAULT_APP_URL).chomp("/")}#{path}"
  end

  def self.page_url
    base = URI.parse(url)
    return base.to_s if base.path.to_s.end_with?(".aspx")

    URI.join(base.to_s.end_with?("/") ? base.to_s : "#{base}/", DEFAULT_PAGE).to_s
  end

  def self.request_uri(params)
    uri = URI.parse(page_url)
    uri.query = URI.encode_www_form(params.slice(*FIELDS))
    uri
  end

  def self.deliver!(kind, params)
    response, final_uri = fetch(request_uri(params))
    where = "[#{final_uri.scheme}://#{final_uri.host}#{final_uri.path}]"
    raise DeliveryError, "Mail service asked for a login #{where}" if login_page?(final_uri)
    raise DeliveryError, "#{failure_message(response)} #{where}" unless success?(response)

    Rails.logger.info("LeapMailRelay sent kind=#{kind} to=#{params['to_email']} status=#{response.code} #{where} krai_said=#{reply_text(response).inspect}")
    true
  end

  # krai's page may answer with a redirect (302 "Object moved") to a result
  # page; follow it and judge the page it ends on.
  def self.fetch(uri)
    response = get(uri)
    MAX_REDIRECTS.times do
      break unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = URI.join(uri.to_s, response["location"])
      response = get(uri)
    end
    [ response, uri ]
  end

  def self.get(uri)
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept"] = "application/json"

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(request)
    end
  end

  def self.login_page?(uri)
    uri.path.to_s.downcase.match?(/login|signin|sign_in/)
  end

  # krai answers 200 with an HTML message, also when it refused to send, so the
  # page text decides; a JSON answer can say "success": false or "status": "error".
  def self.success?(response)
    return false unless response.is_a?(Net::HTTPSuccess)

    body = parsed_body(response)
    unless body.is_a?(Hash)
      text = reply_text(response)
      return text.match?(KRAI_SENT) || !text.match?(KRAI_REFUSED)
    end
    return false if body.key?("success") && !ActiveModel::Type::Boolean.new.cast(body["success"])

    !body["status"].to_s.downcase.in?(%w[error failed failure])
  end

  def self.failure_message(response)
    body = parsed_body(response)
    detail = body["message"] || body["error"] if body.is_a?(Hash)
    detail ||= reply_text(response)
    "Mail service returned #{response.code}: #{detail.presence || response.message}"
  end

  def self.reply_text(response)
    response.body.to_s.gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, " ").gsub(/<[^>]+>/, " ").squish.first(200)
  end

  def self.parsed_body(response)
    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    nil
  end
end

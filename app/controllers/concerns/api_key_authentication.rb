# Lets report tools (Power BI, Excel "From Web") read the read-only GET APIs
# without the login form, so dashboards refresh live from LEAP. The tool sends
# LEAP_API_KEY as ?api_key=..., an X-Api-Key header or "Authorization: Bearer ...",
# and the request runs as the API user (LEAP_API_USER_LOGIN, else the first
# admin). Off until LEAP_API_KEY is set; browser logins work as before.
#
# Include only in controllers whose actions just read data.
module ApiKeyAuthentication
  extend ActiveSupport::Concern
  MIN_KEY_LENGTH = 32

  included do
    prepend_before_action :authenticate_with_api_key
  end

  private

  def authenticate_with_api_key
    given = request_api_key
    return if given.blank?

    expected = ENV["LEAP_API_KEY"].to_s
    if request.get? && expected.length >= MIN_KEY_LENGTH && ActiveSupport::SecurityUtils.secure_compare(given, expected) && api_key_user
      @api_key_authenticated = true
    else
      render json: { error: "Invalid API key." }, status: :unauthorized
    end
  end

  # ApplicationController#current_user only reads the session.
  def current_user
    @api_key_authenticated ? api_key_user : super
  end

  def request_api_key
    params[:api_key].presence ||
      request.headers["X-Api-Key"].presence ||
      request.authorization.to_s[/\ABearer\s+(.+)\z/, 1]
  end

  def api_key_user
    @api_key_user ||= User.find_by(login: ENV["LEAP_API_USER_LOGIN"].presence) || User.where(role: "admin").order(:id).first
  end
end

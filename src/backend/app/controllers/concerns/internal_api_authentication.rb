module InternalApiAuthentication
  extend ActiveSupport::Concern

  INTERNAL_API_SECRET_HEADER = "X-Internal-API-Secret"
  INTERNAL_SESSION_TOKEN_HEADER = "X-Internal-Session-Token"

  included do
    before_action :authenticate_internal_api_secret!
  end

  private

  def authenticate_internal_api_secret!
    head :forbidden unless internal_api_secret_valid?
  end

  def authenticate_internal_session!
    head :unauthorized if current_user.nil?
  end

  def current_user
    @current_user ||= current_session&.user
  end

  def current_session
    @current_session ||= begin
      token = request.headers[INTERNAL_SESSION_TOKEN_HEADER].to_s
      token.present? ? UserSession.find_active_by_token(token) : nil
    end
  end

  def internal_api_secret_valid?
    expected_secret = ENV["INTERNAL_API_SECRET"].to_s
    provided_secret = request.headers[INTERNAL_API_SECRET_HEADER].to_s

    return false if expected_secret.blank? || provided_secret.blank?
    return false if expected_secret.bytesize != provided_secret.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected_secret, provided_secret)
  end
end

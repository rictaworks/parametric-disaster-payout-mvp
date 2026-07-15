require "json"
require "net/http"

class RecaptchaVerifier
  VERIFY_URI = URI("https://www.google.com/recaptcha/api/siteverify")
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5

  def valid?(token)
    secret = ENV["RECAPTCHA_SECRET_KEY"].to_s
    return false if secret.blank? || token.blank?

    payload = JSON.parse(fetch_verification(secret, token))
    success = payload.fetch("success", false) == true

    unless success
      Rails.logger.warn("RecaptchaVerifier: verification rejected, error-codes=#{payload['error-codes'].inspect}")
    end

    success
  rescue StandardError => e
    Rails.logger.error("RecaptchaVerifier: verification request failed (#{e.class}): #{e.message}")
    false
  end

  private

  def fetch_verification(secret, token)
    Net::HTTP.start(
      VERIFY_URI.host,
      VERIFY_URI.port,
      use_ssl: true,
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ) do |http|
      http.post(VERIFY_URI.path, URI.encode_www_form(secret: secret, response: token)).body
    end
  end
end

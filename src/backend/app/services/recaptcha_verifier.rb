require "json"
require "net/http"

class RecaptchaVerifier
  VERIFY_URI = URI("https://www.google.com/recaptcha/api/siteverify")

  def valid?(token)
    secret = ENV["RECAPTCHA_SECRET_KEY"].to_s
    return false if secret.blank? || token.blank?

    response = Net::HTTP.post_form(VERIFY_URI, {
      "secret" => secret,
      "response" => token
    })

    JSON.parse(response.body).fetch("success", false) == true
  rescue StandardError
    false
  end
end

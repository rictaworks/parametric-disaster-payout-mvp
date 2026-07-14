module Api
  module V1
    class SessionsController < ApplicationController
      INTERNAL_API_SECRET_HEADER = "X-Internal-API-Secret"

      def create
        return head :forbidden unless internal_api_secret_valid?

        user = authenticate_user!
        render json: {
          session_token: user.internal_session_token,
          user: {
            id: user.id,
            google_sub: user.google_sub
          }
        }, status: :ok
      rescue Google::Auth::IDTokens::VerificationError
        head :unauthorized
      end

      private

      def authenticate_user!
        User.find_or_create_by!(google_sub: google_sub)
      end

      def google_sub
        return development_google_sub if Rails.env.development?

        claims = Google::Auth::IDTokens.verify_oidc(id_token, aud: ENV.fetch("GOOGLE_CLIENT_ID"))
        claim_sub(claims)
      end

      def claim_sub(claims)
        claims[:sub] || claims["sub"] || raise(Google::Auth::IDTokens::VerificationError, "Missing sub claim")
      end

      def development_google_sub
        "development-user"
      end

      def id_token
        params[:id_token].to_s.tap do |token|
          raise Google::Auth::IDTokens::VerificationError, "Missing id_token" if token.blank?
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
  end
end

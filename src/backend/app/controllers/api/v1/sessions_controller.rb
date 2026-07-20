module Api
  module V1
    class SessionsController < ApplicationController
      include InternalApiAuthentication

      before_action :authenticate_internal_session!, only: :show

      def create
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

      def show
        render json: {
          user: session_user_payload(current_user)
        }, status: :ok
      end

      def destroy
        clear_session_cookie
        head :no_content
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

      def session_user_payload(user)
        {
          id: user.id,
          google_sub: user.google_sub
        }
      end

      def clear_session_cookie
        response.set_header(
          "Set-Cookie",
          [
            "parametric_session_token=",
            "Max-Age=0",
            "Path=/",
            "SameSite=Lax",
            "HttpOnly",
            (Rails.env.production? ? "Secure" : nil)
          ].compact.join("; ")
        )
      end
    end
  end
end

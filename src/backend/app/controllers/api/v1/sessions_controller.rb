module Api
  module V1
    # POST /api/v1/session
    # このAPIはNext.jsサーバーサイドからのみ呼ばれる（INTERNAL_API_SECRETで保護）。
    # ブラウザから直接到達できない設計になっている。
    class SessionsController < Api::V1::BaseController
      include ActionController::Cookies

      def create
        token = params[:id_token]

        google_sub = verify_google_id_token(token)

        unless google_sub
          return render json: { error: "Invalid ID token" }, status: :unauthorized
        end

        user = User.find_or_create_by!(google_sub: google_sub)
        session[:user_id] = user.id

        render json: { user_id: user.id }, status: :ok
      end

      private

      def verify_google_id_token(token)
        return nil if token.blank?

        if Rails.env.development?
          return token if token.start_with?("dev_")
        end

        uri = URI("https://oauth2.googleapis.com/tokeninfo?id_token=#{URI.encode_www_form_component(token)}")
        response = Net::HTTP.get_response(uri)

        return nil unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)

        expected_aud = ENV.fetch("GOOGLE_CLIENT_ID", nil)
        return nil if expected_aud.present? && payload["aud"] != expected_aud

        payload["sub"]
      rescue StandardError
        nil
      end
    end
  end
end

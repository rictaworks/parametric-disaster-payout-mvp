module Api
  class BaseController < ApplicationController
    skip_before_action :authenticate_user!

    before_action :verify_internal_api_secret

    private

    def verify_internal_api_secret
      secret = ENV.fetch("INTERNAL_API_SECRET", nil)
      provided = request.headers["X-Internal-Api-Secret"]

      return if secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret, provided.to_s)

      render json: { error: "Forbidden" }, status: :forbidden
    end
  end
end

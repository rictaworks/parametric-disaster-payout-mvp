module Admin
  module Api
    class PayoutsController < ApplicationController
      include ActionController::HttpAuthentication::Basic::ControllerMethods

      before_action :authenticate_admin!

      def complete
        payout = Payout.find(params[:id])
        result = ExecutePayout.new(payout: payout).call

        if result.success?
          render json: { payout: serialize_payout(result.payout) }
        else
          render json: { error: I18n.t("admin_api.payouts.invalid_status_transition") }, status: result.status
        end
      end

      private

      def authenticate_admin!
        authenticate_or_request_with_http_basic do |username, password|
          secure_compare(username, ENV["ADMIN_BASIC_USER"]) && secure_compare(password, ENV["ADMIN_BASIC_PASSWORD"])
        end
      end

      def secure_compare(provided, expected)
        provided = provided.to_s
        expected = expected.to_s

        return false if provided.blank? || expected.blank?
        return false if provided.bytesize != expected.bytesize

        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def serialize_payout(payout)
        {
          id: payout.id,
          payout_status_code: payout.payout_status.code,
          policy_status_code: payout.policy.reload.policy_status.code
        }
      end
    end
  end
end

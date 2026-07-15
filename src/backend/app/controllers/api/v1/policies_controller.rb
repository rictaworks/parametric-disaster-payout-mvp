module Api
  module V1
    class PoliciesController < ApplicationController
      INTERNAL_API_SECRET_HEADER = "X-Internal-API-Secret"

      before_action :authenticate_internal_api_secret!
      before_action :authenticate_internal_session!

      def create
        result = ValidateAndCreatePolicy.new(
          user: current_user,
          plan_id: policy_params[:plan_id],
          station_id: policy_params[:station_id],
          payout_tier_id: policy_params[:payout_tier_id],
          threshold: policy_params[:threshold],
          recaptcha_token: policy_params[:recaptcha_token]
        ).call

        if result.success?
          render json: { policy: serialize_policy(result.policy) }, status: :created
        else
          render json: { error: result.error, details: result.details }, status: result.status
        end
      end

      private

      def authenticate_internal_session!
        head :unauthorized if current_user.nil?
      end

      def authenticate_internal_api_secret!
        head :forbidden unless internal_api_secret_valid?
      end

      def current_user
        @current_user ||= begin
          token = request.headers["X-Internal-Session-Token"].to_s
          token.present? ? User.find_signed(token, purpose: :internal_session) : nil
        end
      end

      def policy_params
        params.permit(:plan_id, :station_id, :payout_tier_id, :threshold, :recaptcha_token)
      end

      def serialize_policy(policy)
        {
          id: policy.id,
          user_id: policy.user_id,
          plan_id: policy.plan_id,
          station_id: policy.station_id,
          payout_tier_id: policy.payout_tier_id,
          policy_status_id: policy.policy_status_id,
          threshold: policy.threshold,
          waiting_until: policy.waiting_until&.iso8601,
          expires_at: policy.expires_at&.iso8601
        }
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

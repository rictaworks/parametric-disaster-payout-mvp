module Api
  module V1
    class PoliciesController < ApplicationController
      include InternalApiAuthentication

      before_action :authenticate_internal_session!

      def index
        policies = current_user.policies.includes(:plan, :station, :payout_tier, :policy_status).order(created_at: :desc)

        render json: { policies: policies.map { |policy| serialize_policy(policy) } }
      end

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

      def policy_params
        params.permit(:plan_id, :station_id, :payout_tier_id, :threshold, :recaptcha_token)
      end

      def serialize_policy(policy)
        {
          id: policy.id,
          user_id: policy.user_id,
          plan_id: policy.plan_id,
          plan_code: policy.plan.code,
          station_id: policy.station_id,
          station_code: policy.station&.code,
          payout_tier_id: policy.payout_tier_id,
          payout_tier_code: policy.payout_tier.code,
          policy_status_id: policy.policy_status_id,
          policy_status_code: policy.policy_status.code,
          threshold: policy.threshold,
          waiting_until: policy.waiting_until&.iso8601,
          expires_at: policy.expires_at&.iso8601
        }
      end
    end
  end
end

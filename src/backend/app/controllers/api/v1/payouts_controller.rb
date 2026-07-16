module Api
  module V1
    class PayoutsController < ApplicationController
      include InternalApiAuthentication

      before_action :authenticate_internal_session!

      def index
        payouts = current_user.payouts.includes(:policy, :payout_status, :payout_tier, :survey_response).order(created_at: :desc)

        render json: { payouts: payouts.map { |payout| serialize_payout(payout) } }
      end

      private

      def serialize_payout(payout)
        {
          id: payout.id,
          policy_id: payout.policy_id,
          policy_plan_code: payout.policy.plan.code,
          policy_station_code: payout.policy.station&.code,
          policy_status_code: payout.policy.policy_status.code,
          policy_threshold: payout.policy.threshold,
          payout_tier_code: payout.payout_tier.code,
          payout_tier_amount_yen: payout.payout_tier.amount_yen,
          payout_status_code: payout.payout_status.code,
          survey_response_submitted: payout.survey_response.present?,
          decided_at: payout.decided_at&.iso8601,
          created_at: payout.created_at.iso8601
        }
      end
    end
  end
end

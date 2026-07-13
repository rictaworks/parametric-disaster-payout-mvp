module Api
  module V1
    # POST /api/v1/policies
    # 契約登録API（F1 validateAndCreatePolicy）
    # 本サービスは保険（デモ）であり実際の金銭のお支払いは発生しません。
    class PoliciesController < ApplicationController
      def create
        result = ValidateAndCreatePolicy.new(
          user:            current_user,
          plan_id:         params[:plan_id],
          station_id:      params[:station_id],
          payout_tier_id:  params[:payout_tier_id],
          recaptcha_token: params[:recaptcha_token]
        ).call

        if result.success?
          render json: policy_json(result.policy), status: :created
        else
          render json: { error: result.error }, status: error_status(result.error_code)
        end
      end

      private

      def policy_json(policy)
        {
          id:             policy.id,
          plan_id:        policy.plan_id,
          station_id:     policy.station_id,
          payout_tier_id: policy.payout_tier_id,
          status:         policy.policy_status.code,
          waiting_until:  policy.waiting_until.iso8601,
          expires_at:     policy.expires_at.iso8601,
          created_at:     policy.created_at.iso8601
        }
      end

      def error_status(error_code)
        case error_code
        when :recaptcha_failed  then :bad_request          # 400
        when :master_not_found  then :unprocessable_content # 422
        when :duplicate_policy  then :conflict             # 409
        else                         :unprocessable_content # 422
        end
      end
    end
  end
end

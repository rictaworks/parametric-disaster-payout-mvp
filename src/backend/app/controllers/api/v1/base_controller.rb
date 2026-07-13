module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_internal_api!

      private

      def authenticate_internal_api!
        return if Rails.env.test?

        expected = ENV.fetch('INTERNAL_API_SECRET', 'dev-secret')
        header = request.headers['Authorization'].to_s
        provided = header.delete_prefix('Bearer ').presence || header

        return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

        render json: { error: 'Unauthorized' }, status: :unauthorized
      end

      def locale_code
        requested = params[:locale].presence || 'ja'
        %w[ja en fr zh ru es ar].include?(requested) ? requested : 'ja'
      end

      def serialize_plan(plan)
        {
          id: plan.id,
          code: plan.code,
          plan_type: plan.plan_type,
          label: plan.localized_label(locale_code)
        }
      end

      def serialize_station(station)
        {
          id: station.id,
          code: station.code,
          plan_type: station.plan_type,
          label: station.localized_label(locale_code),
          prefecture: station.prefecture
        }
      end

      def serialize_payout_tier(tier)
        {
          id: tier.id,
          code: tier.code,
          amount_jpy: tier.amount_jpy,
          label: tier.localized_label(locale_code)
        }
      end

      def serialize_policy(policy)
        {
          id: policy.id,
          status: policy.policy_status.code,
          plan: serialize_plan(policy.plan),
          station: serialize_station(policy.station),
          threshold: policy.threshold,
          payout_tier: serialize_payout_tier(policy.payout_tier),
          created_at: policy.created_at.iso8601,
          waiting_until: policy.waiting_until.iso8601
        }
      end
    end
  end
end

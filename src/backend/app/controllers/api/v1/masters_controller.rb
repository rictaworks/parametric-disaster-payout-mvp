module Api
  module V1
    class MastersController < ApplicationController
      include InternalApiAuthentication

      def index
        render json: {
          plans: Plan.order(:code).map { |plan| serialize_plan(plan) },
          stations: Station.order(:code).map { |station| serialize_station(station) },
          payout_tiers: PayoutTier.order(:code).map { |payout_tier| serialize_payout_tier(payout_tier) }
        }
      end

      private

      def serialize_plan(plan)
        { id: plan.id, code: plan.code, trigger_type: plan.trigger_type }
      end

      def serialize_station(station)
        { id: station.id, code: station.code, measurement_type: station.measurement_type }
      end

      def serialize_payout_tier(payout_tier)
        { id: payout_tier.id, code: payout_tier.code, amount_yen: payout_tier.amount_yen }
      end
    end
  end
end

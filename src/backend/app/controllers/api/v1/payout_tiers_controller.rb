module Api
  module V1
    class PayoutTiersController < BaseController
      def index
        render json: PayoutTier.order(:amount_jpy).map { |tier| serialize_payout_tier(tier) }
      end
    end
  end
end

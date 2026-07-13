module Admin
  module Api
    class PayoutsController < Admin::BaseController
      # PATCH /admin/api/payouts/:id/complete
      def complete
        payout = Payout.find(params[:id])

        if payout.status == "completed"
          render json: { error: "すでに支払完了済みです" }, status: :unprocessable_entity
          return
        end

        result = CompletePayout.new(payout: payout).call

        render json: {
          payout: {
            id: result.id,
            status: result.status,
            amount: result.amount,
            policy_id: result.policy_id,
            updated_at: result.updated_at
          },
          message: "模擬支払が完了しました"
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "支払指図が見つかりません" }, status: :not_found
      end
    end
  end
end

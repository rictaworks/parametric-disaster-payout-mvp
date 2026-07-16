module Admin
  module Api
    class PayoutsController < ApplicationController
      include Admin::Authentication

      def complete
        payout = Payout.find(params[:id])
        result = ExecutePayout.new(payout: payout).call
        render_transition_response(result)
      end

      def invalidate
        payout = Payout.find(params[:id])
        result = invalidate_payout(payout)
        render_transition_response(result)
      end

      private

      Result = Struct.new(:payout, :status, keyword_init: true) do
        def success?
          status == :ok
        end
      end

      def serialize_payout(payout)
        {
          id: payout.id,
          payout_status_code: payout.payout_status.code,
          policy_status_code: payout.policy.reload.policy_status.code
        }
      end

      def invalidate_payout(payout)
        return Result.new(payout: payout, status: :ok) if payout.payout_status.code == "invalid"
        return Result.new(payout: payout, status: :unprocessable_entity) unless payout.payout_status.code == "ordered"

        invalid_status = PayoutStatus.find_by!(code: "invalid")
        payout.update!(payout_status: invalid_status)
        Result.new(payout: payout.reload, status: :ok)
      end

      def render_transition_response(result)
        if result.success?
          return_to = params[:return_to].presence

          if return_to.present?
            redirect_to return_to, status: :see_other
          else
            render json: { payout: serialize_payout(result.payout) }
          end
        else
          render json: { error: I18n.t("admin_api.payouts.invalid_status_transition") }, status: result.status
        end
      end
    end
  end
end

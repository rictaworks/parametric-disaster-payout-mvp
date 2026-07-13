module Api
  module V1
    class PoliciesController < BaseController
      def index
        user = User.find_by(google_sub: params[:google_sub])
        render json: [] and return unless user

        policies = Policy.includes(:plan, :station, :payout_tier, :policy_status)
                         .where(user: user)
                         .order(created_at: :desc)

        render json: policies.map { |policy| serialize_policy(policy) }
      end

      def create
        user = User.find_or_create_by!(google_sub: policy_params.fetch(:google_sub))
        result = ValidateAndCreatePolicy.call(
          user_id: user.id,
          plan_id: policy_params[:plan_id],
          station_id: policy_params[:station_id],
          threshold: policy_params[:threshold],
          payout_tier_id: policy_params[:payout_tier_id],
          recaptcha_token: policy_params[:recaptcha_token],
          age_group: policy_params[:age_group]
        )

        if result[:success]
          render json: serialize_policy(result[:policy]), status: :created
        else
          render json: { error: result[:error] }, status: result[:code]
        end
      end

      private

      def policy_params
        params.permit(:google_sub, :plan_id, :station_id, :threshold, :payout_tier_id, :recaptcha_token, :age_group)
      end
    end
  end
end

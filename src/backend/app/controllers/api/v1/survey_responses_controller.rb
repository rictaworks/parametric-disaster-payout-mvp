module Api
  module V1
    class SurveyResponsesController < ApplicationController
      include InternalApiAuthentication

      before_action :authenticate_internal_session!

      def create
        payout = Payout.includes(:policy, :payout_status).find(survey_response_params[:payout_id])
        return head :forbidden unless payout.policy.user_id == current_user.id

        unless payout.payout_status.code == "completed_simulated"
          render json: { error: [ I18n.t("api.survey_responses.payout_must_be_completed") ] }, status: :unprocessable_entity
          return
        end

        survey_response = current_user.survey_responses.create!(
          payout: payout,
          response_data: survey_response_params[:response_data]
        )

        render json: { survey_response: serialize_survey_response(survey_response) }, status: :created
      rescue ActiveRecord::RecordNotFound
        head :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      private

      def survey_response_params
        params.permit(:payout_id, response_data: {})
      end

      def serialize_survey_response(survey_response)
        {
          id: survey_response.id,
          payout_id: survey_response.payout_id,
          response_data: survey_response.response_data,
          created_at: survey_response.created_at.iso8601
        }
      end
    end
  end
end

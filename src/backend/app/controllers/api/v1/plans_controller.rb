module Api
  module V1
    class PlansController < BaseController
      def index
        render json: Plan.order(:id).map { |plan| serialize_plan(plan) }
      end
    end
  end
end

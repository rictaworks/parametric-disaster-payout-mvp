module Api
  module V1
    class StationsController < BaseController
      def index
        render json: Station.order(:id).map { |station| serialize_station(station) }
      end
    end
  end
end

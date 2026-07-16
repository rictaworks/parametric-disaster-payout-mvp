module Api
  module V1
    class NotificationsController < ApplicationController
      include InternalApiAuthentication

      before_action :authenticate_internal_session!

      def index
        notifications = current_user.notifications.order(created_at: :desc)

        render json: { notifications: notifications.map { |notification| serialize_notification(notification) } }
      end

      private

      def serialize_notification(notification)
        {
          id: notification.id,
          kind: notification.kind,
          message: notification.message,
          policy_id: notification.policy_id,
          payout_id: notification.payout_id,
          delivered_at: notification.delivered_at&.iso8601,
          read_at: notification.read_at&.iso8601,
          created_at: notification.created_at.iso8601
        }
      end
    end
  end
end

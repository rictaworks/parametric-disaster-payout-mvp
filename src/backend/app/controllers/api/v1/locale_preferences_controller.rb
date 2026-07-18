module Api
  module V1
    class LocalePreferencesController < ApplicationController
      include InternalApiAuthentication

      before_action :authenticate_internal_session!

      def update
        unless User::SUPPORTED_LOCALES.include?(locale_param)
          render json: { error: I18n.t("api.locale_preferences.invalid_locale") }, status: :unprocessable_entity
          return
        end

        current_user.update!(locale: locale_param)
        render json: { user: { id: current_user.id, locale: current_user.locale } }
      end

      private

      def locale_param
        params[:locale].to_s
      end
    end
  end
end

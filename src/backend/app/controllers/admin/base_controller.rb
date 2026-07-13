module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin!

    private

    def authenticate_admin!
      credentials = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
      unless credentials &&
             credentials[0] == ENV.fetch("ADMIN_BASIC_AUTH_USER", "admin") &&
             credentials[1] == ENV.fetch("ADMIN_BASIC_AUTH_PASSWORD", "password")
        request_http_basic_authentication("Admin Area")
      end
    end
  end
end

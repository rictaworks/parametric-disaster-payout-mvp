module Admin
  module Authentication
    extend ActiveSupport::Concern

    include ActionController::HttpAuthentication::Basic::ControllerMethods

    included do
      before_action :authenticate_admin!
    end

    private

    def authenticate_admin!
      authenticate_or_request_with_http_basic do |username, password|
        secure_compare(username, ENV["ADMIN_BASIC_USER"]) && secure_compare(password, ENV["ADMIN_BASIC_PASSWORD"])
      end
    end

    def secure_compare(provided, expected)
      provided = provided.to_s
      expected = expected.to_s

      return false if provided.blank? || expected.blank?
      return false if provided.bytesize != expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end

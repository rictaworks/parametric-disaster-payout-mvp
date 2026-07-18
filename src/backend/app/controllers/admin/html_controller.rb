module Admin
  class HtmlController < ActionController::Base
    protect_from_forgery with: :exception

    include Admin::Authentication

    layout "admin"
  end
end

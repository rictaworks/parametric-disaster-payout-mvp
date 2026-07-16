module Admin
  class HtmlController < ActionController::Base
    include Admin::Authentication

    layout "admin"
  end
end

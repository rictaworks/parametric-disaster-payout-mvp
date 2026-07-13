class ApplicationController < ActionController::API
  include ActionController::Cookies

  before_action :authenticate_user!

  private

  def authenticate_user!
    if Rails.env.development? && ENV["SKIP_AUTH"] == "true"
      @current_user = User.find_or_create_by!(google_sub: "dev_user_sub")
      return
    end

    user_id = session[:user_id]
    @current_user = User.find_by(id: user_id) if user_id
    render json: { error: "Unauthorized" }, status: :unauthorized unless @current_user
  end

  def current_user
    @current_user
  end
end

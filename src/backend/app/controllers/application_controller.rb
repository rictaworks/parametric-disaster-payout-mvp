class ApplicationController < ActionController::API
  def health
    render json: { status: 'ok' }
  end
end

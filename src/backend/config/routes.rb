Rails.application.routes.draw do
  get '/up', to: 'application#health'

  namespace :api do
    namespace :v1 do
      resources :plans, only: [:index]
      resources :stations, only: [:index]
      resources :payout_tiers, only: [:index]
      resources :policies, only: [:index, :create]
    end
  end
end

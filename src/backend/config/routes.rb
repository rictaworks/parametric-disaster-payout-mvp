Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "session", to: "sessions#create"
      patch "locale", to: "locale_preferences#update"
      get "policies", to: "policies#index"
      post "policies", to: "policies#create"
      patch "policies/:id/cancel", to: "policies#cancel"
      patch "policies/:id/force_waiting_period_elapsed", to: "policies#force_waiting_period_elapsed"
      get "payouts", to: "payouts#index"
      get "notifications", to: "notifications#index"
      post "survey_responses", to: "survey_responses#create"
      get "masters", to: "masters#index"
    end
  end

  namespace :admin do
    root to: "policies#index"
    get "kpi", to: "kpi#index"
    get "payouts", to: "payouts#index"
    get "simulated_events", to: "simulated_events#index"
    post "simulated_events", to: "simulated_events#create"
    get "reset", to: "reset#index"
    post "reset", to: "reset#create"

    namespace :api do
      patch "payouts/:id/complete", to: "payouts#complete"
      patch "payouts/:id/invalidate", to: "payouts#invalidate"
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end

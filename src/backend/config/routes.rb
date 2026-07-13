Rails.application.routes.draw do
  # ヘルスチェック
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # 認証（Next.js BFFサーバーサイドからのみ利用）
      resource :session, only: [ :create ]

      # 契約登録API（F1 validateAndCreatePolicy）
      resources :policies, only: [ :create ]
    end
  end
end

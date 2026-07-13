# Be sure to restart your server when you modify this file.

# CORS設定: Next.js BFF（サーバーサイド）からのリクエストを許可
# フロントエンドURLは FRONTEND_URL 環境変数で設定すること

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_URL", "http://localhost:3000")

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true
  end
end

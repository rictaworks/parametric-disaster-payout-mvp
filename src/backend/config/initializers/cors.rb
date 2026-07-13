# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

# CORS settings are configured primarily for the development environment.
# Under the approved architecture, the browser communicates only with the frontend (Next.js),
# and the Rails API is called exclusively via the Next.js BFF (Server-Side).
# To conceal the backend domain, do NOT expose FRONTEND_ORIGIN to public domain in production CORS settings.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000")

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :options, :head ]
  end
end

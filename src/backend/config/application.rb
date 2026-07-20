require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # 管理画面（/admin）のCSRF保護にのみセッションCookieを使用する。
    # メインのJSON API（Next.js BFF向け）はGoogleログイン＋opaqueなsubのみで
    # 認証しており、セッションCookieを必要としないため、path指定でスコープを
    # /admin配下に限定し、ブラウザが他経路にこのCookieを送らないようにする
    config.session_store :cookie_store, key: "_backend_admin_session", path: "/admin", same_site: :strict
    config.middleware.use ActionDispatch::Cookies
    # config.api_only = true の場合、Railsは config.session_store の設定を
    # ミドルウェアへ自動で渡さないため、config.session_store / config.session_options を
    # 明示的に渡す（引数なしで ActionDispatch::Session::CookieStore を use すると
    # key・path・same_site が既定値（_session_id・Path=/）にフォールバックしてしまう）
    config.middleware.use config.session_store, config.session_options
    # config.api_only = true では ActionDispatch::Flash もミドルウェアスタックから
    # 自動で外れるため、管理画面（app/views/layouts/admin.html.erb）が使う
    # flash を有効にするために明示的に追加する（Issue #62）。セッションに依存するため
    # ActionDispatch::Cookies / セッションストアの後に追加すること。
    config.middleware.use ActionDispatch::Flash
    # config.api_only = true では Rack::MethodOverride も自動で外れるため、
    # 管理画面（button_to method: :patch 等）が送信する <form method="post"> ＋
    # 隠しフィールド _method=patch を PATCH リクエストへ変換するために追加する（Issue #87）。
    config.middleware.use Rack::MethodOverride
  end
end

module Admin
  module Authentication
    extend ActiveSupport::Concern

    include ActionController::HttpAuthentication::Basic::ControllerMethods

    included do
      before_action :authenticate_admin!
      around_action :use_japanese_locale
    end

    private

    # 開発者用の管理画面は日本語のみ対応のため、アプリ全体のデフォルトロケールに
    # 依存せずこのnamespace配下では常に:jaへ固定する
    def use_japanese_locale(&block)
      I18n.with_locale(:ja, &block)
    end

    def authenticate_admin!
      authenticate_or_request_with_http_basic do |username, password|
        secure_compare(username, ENV["ADMIN_BASIC_USER"]) && secure_compare(password, ENV["ADMIN_BASIC_PASSWORD"])
      end
    end

    def secure_compare(provided, expected)
      provided = provided.to_s
      expected = expected.to_s

      return false if provided.blank? || expected.blank?
      return false if provided.bytesize != expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end

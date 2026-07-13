require "webmock/rspec"

# reCAPTCHAのHTTPリクエストをデフォルトで無効化
WebMock.disable_net_connect!(allow_localhost: true)

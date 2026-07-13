require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.consider_all_requests_local = true
  config.eager_load = false
  config.active_support.deprecation = :stderr
end

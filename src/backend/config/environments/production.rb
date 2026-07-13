require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.consider_all_requests_local = false
  config.eager_load = true
end

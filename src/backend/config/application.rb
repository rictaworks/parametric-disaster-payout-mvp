require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

Bundler.require(*Rails.groups)

module ParametricDisasterPayoutBackend
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.generators do |generator|
      generator.test_framework :rspec
      generator.helper false
      generator.assets false
      generator.stylesheets false
    end
  end
end

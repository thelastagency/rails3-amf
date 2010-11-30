require 'rocketamf'
require 'rails'

#require 'rails3-amf/serialization' fosrias: See rubyamf/extensions/serialization
require 'rails3-amf/action_controller'
require 'rails3-amf/configuration'
require 'rails3-amf/request_parser'
require 'rails3-amf/request_processor'

require 'rubyamf/util/string'
require 'rubyamf/extensions/fault_object'
require 'rubyamf/extensions/rocketamf'
require 'rubyamf/extensions/configuration'
require 'rubyamf/extensions/serialization'
require 'rubyamf/extensions/deserialization'

module Rails3AMF
  class Railtie < Rails::Railtie
    config.rails3amf = Rails3AMF::Configuration.new

    initializer "rails3amf.middleware" do
      config.app_middleware.use Rails3AMF::RequestParser, config.rails3amf, Rails.logger
      config.app_middleware.use Rails3AMF::RequestProcessor, config.rails3amf, Rails.logger
    end

    # RubyAMF mapping accesses models by class, so we load the mapping after the application initializes so
    # autoloading works.
    config.after_initialize do
      load File.expand_path(::Rails.root.to_s) + '/config/rubyamf_config.rb'
    end
  end
end

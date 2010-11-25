require 'rocketamf'
require 'rails'

require 'rails3-amf/serialization'
require 'rails3-amf/action_controller'
require 'rails3-amf/configuration'
require 'rails3-amf/request_parser'
require 'rails3-amf/request_processor'

require 'rubyamf/rails3/rails3_serialization' #In this order to override default serialization
require 'rubyamf/rails3/rails3_configuration'
require 'rubyamf/rails3/fault_object'

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

      # If we use array collections, we override how arrays are written.
      require 'rubyamf/array_collection_serializer' if RubyAMF::Configuration::ClassMappings.use_array_collection

      #Map FaultObject for Rails 3 which extends RocketAMF::Values::ErrorMessage
      RocketAMF::ClassMapper.define do |m|
        m.map :as => 'flex.messaging.messages.ErrorMessage', :ruby => 'FaultObject'
      end
    end
  end
end

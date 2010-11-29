require 'action_controller/railtie'
require 'rubyamf/app/configuration'

Mime::Type.register "application/x-amf", :amf

module ActionController
  Base.class_eval do
    attr_accessor :rubyamf_params # this way they can always access the rubyamf_params
    
    def is_amf
      request.format("") == Mime::AMF
    end
  end

  module Renderers
    attr_reader :amf_response

    add :amf do |amf, options|
      @amf_response = if amf.respond_to?(:to_amf)
        # Sets scope in the map
        RubyAMF::Configuration::ClassMappings.current_mapping_scope = options[:class_mapping_scope]||RubyAMF::Configuration::ClassMappings.default_mapping_scope
        amf.to_amf(options) # This enables using options directly in the render block instead of calling @user.to_amf(options) in the block. This conforms to to_xml and to_json rendering functionality.
      elsif amf.is_a?(FaultObject) # Allows rendering legacy FaultObject
        amf.error_message request
       else
        amf
      end
      self.content_type ||= Mime::AMF
      self.response_body = " "
    end
  end
end
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
        RubyAMF::Configuration::ClassMappings.current_mapping_scope = options[:class_mapping_scope]||RubyAMF::Configuration::ClassMappings.default_mapping_scope
        amf.to_amf(options)
      else
        amf
      end
      self.content_type ||= Mime::AMF
      self.response_body = " "
    end
  end
end
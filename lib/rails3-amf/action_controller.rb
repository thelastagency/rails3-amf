require 'action_controller/railtie'

Mime::Type.register "application/x-amf", :amf

module ActionController
  module Renderers
    attr_reader :amf_response

    add :amf do |amf, options|
      @amf_response = amf.respond_to?(:to_amf) ? amf.to_amf(options) : amf
      self.content_type ||= Mime::AMF
      self.response_body = " "
    end
  end
end
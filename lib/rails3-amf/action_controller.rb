require 'action_controller/railtie'
require 'rubyamf/app/configuration'
require 'rubyamf/app/request_store'

Mime::Type.register "application/x-amf", :amf

module ActionController

  # All of this is legacy functionality
  Base.class_eval do
    attr_accessor :is_amf
    attr_accessor :is_rubyamf
    attr_accessor :rubyamf_params # this way they can always access the rubyamf_params

     #Higher level "credentials" method that returns credentials whether or not
    #it was from setRemoteCredentials, or setCredentials
    def credentials
      return empty_auth = {:username => nil, :password => nil} #REFACTOR so following works
      empty_auth = {:username => nil, :password => nil}
      amf_credentials||html_credentials||empty_auth #return an empty auth, this watches out for being the cause of an exception, (nil[])
    end

    private
    #setCredentials access
    def amf_credentials
      RubyAMF::App::RequestStore.rails_authentication
    end

    #remoteObject setRemoteCredentials retrieval
    def html_credentials
      auth_data = request.env['RAW_POST_DATA']
      auth_data = auth_data.scan(/DSRemoteCredentials\006.([A-Za-z0-9\+\/=]*).*?\006/)[0][0]
      auth_data.gsub!("DSRemoteCredentialsCharset", "")
      if auth_data.size > 0

        remote_auth = Base64.decode64(auth_data).split(':')[0..1]
      else
        return nil
      end
      case RubyAMF::Configuration::ClassMappings.hash_key_access
        when :string then
          return {'username' => remote_auth[0], 'password' => remote_auth[1]}
        when :symbol then
          return {:username => remote_auth[0], :password => remote_auth[1]}
        when :indifferent then
          return HashWithIndifferentAccess.new({:username => remote_auth[0], :password => remote_auth[1]})
      end
    end
  end

  module Renderers
    attr_reader :amf_response

    add :amf do |amf, options|
      @amf_response = if amf.respond_to?(:to_amf)
        # Sets scope in the map
        RubyAMF::Configuration::ClassMappings.current_mapping_scope = options[:class_mapping_scope]||RubyAMF::Configuration::ClassMappings.default_mapping_scope
        amf.to_amf(options) # This enables using options directly in the render block instead of calling @user.to_amf(options) in the block. This conforms to to_xml and to_json rendering syntax.

      elsif amf.class.to_s == 'FaultObject' #catch returned FaultObjects - use this check so we don't have to include the fault object module
        amf.error_message
       else
        amf
      end
      self.content_type ||= Mime::AMF
      self.response_body = " "
    end
  end
end
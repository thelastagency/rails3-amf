require 'rubyamf/app/request_store'

module Rails3AMF
  class RequestParser
    include RubyAMF::App
    include RubyAMF::Configuration

    def initialize app, config={}, logger=nil
      @app = app
      @config = config
      @logger = logger || Logger.new(STDERR)
    end

    # If the content type is AMF and the path matches the configured gateway path,
    # it parses the request, creates a response object, and forwards the call
    # to the next middleware. If the amf response is constructed, then it serializes
    # the response and returns it as the response.
    def call env
      return @app.call(env) unless should_handle?(env)

      # Wrap request and response
      env['rack.input'].rewind
      env['rails3amf.request'] = RocketAMF::Envelope.new.populate_from_stream(env['rack.input'].read)
      env['rails3amf.response'] = RocketAMF::Envelope.new

      # Store the request and response for reference
      RubyAMF::App::RequestStore.rails_request = env['rails3amf.request']
      RubyAMF::App::RequestStore.rails_response = env['rails3amf.response']

      # Needs to be implemented
#      RequestStore.auth_header = nil # Aryk: why do we need to rescue this?
#      if (auth_header = amfobj.get_header_by_key('Credentials'))
#        RequestStore.auth_header = auth_header #store the auth header for later
#        case ClassMappings.hash_key_access
#          when :string then
#            auth = {'username' => auth_header.value['userid'], 'password' => auth_header.value['password']}
#          when :symbol then
#            auth = {:username => auth_header.value['userid'], :password => auth_header.value['password']}
#          when :indifferent then
#            auth = HashWithIndifferentAccess.new({:username => auth_header.value['userid'], :password => auth_header.value['password']})
#        end
#        RequestStore.rails_authentication = auth
#      end

      # Pass up the chain to the request processor, or whatever is layered in between
      result = @app.call(env)

      # Calculate length and return response
      if env['rails3amf.response'].constructed?
        @logger.info "Sending back AMF"
        response = env['rails3amf.response'].to_s
        return [200, {"Content-Type" => Mime::AMF.to_s, 'Content-Length' => response.length.to_s}, [response]]
      else
        return result
      end
    end

    # Check if we should handle it based on the environment
    def should_handle? env
      return false unless env['CONTENT_TYPE'] == Mime::AMF
      return false unless [*@config.gateway_path].include?(env['PATH_INFO'])
      true
    end
  end
end
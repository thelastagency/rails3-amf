require 'active_support/dependencies'
require 'rubyamf/extensions/configuration'

module Rails3AMF
  class RequestProcessor
    include RubyAMF::Configuration

    def initialize app, config={}, logger=nil
      @app = app
      @config = config
      @logger = logger || Logger.new(STDERR)
    end

    # Processes the AMF request and forwards the method calls to the corresponding
    # rails controllers. No middleware beyond the request processor will receive
    # anything if the request is a handleable AMF request.
    def call env
      return @app.call(env) unless env['rails3amf.response']

      # Handle each method call
      req = env['rails3amf.request']
      res = env['rails3amf.response']
      res.each_method_call req do |method, args|
        begin
          handle_method method, args, env
        rescue Exception => e
          # Log and re-raise exception
          @logger.error e.to_s+"\n"+e.backtrace.join("\n")
          raise e
        end
      end
    end

    def handle_method method, args, env
      # Parse method and load service
      path = method.split('.')
      method_name = path.pop
      controller_name = path.pop
      controller = get_service controller_name, method_name

      # Create rack request
      new_env = env.dup
      new_env['HTTP_ACCEPT'] = Mime::AMF.to_s # Force amf response
      req = ActionDispatch::Request.new(new_env)

      # Begin legacy rubyamf parameter mapping.
      amf_body_value = []
      args.each_with_index do |obj, i|
        amf_body_value << (obj.is_a?(Hash) ? HashWithIndifferentAccess.new(obj) : obj)
      end

      #process the request
      rubyamf_params = {}
      if amf_body_value && !amf_body_value.empty?
        amf_body_value.each_with_index do |item,i|
          rubyamf_params[i] = item
        end
      end

      req_params = {}

      # put them by default into the parameter hash if they opt for it
      req_params.merge!(rubyamf_params) if ParameterMappings.always_add_to_params

      begin
        #One last update of the parameters hash, this will map custom mappings to the hash, and will override any conflicting from above
        ParameterMappings.update_request_parameters(controller_name, method_name, req_params, rubyamf_params, amf_body_value)
      rescue Exception => e
        raise "There was an error with your parameter mappings: {#{e.message}}"
      end

      req.params.merge!(req_params)

      # End legacy rubyamf parameter mapping

      built_params = build_params(controller_name, method_name, args)

      rubyamf_params.merge!(built_params)

      req.params.merge!(built_params)

      # Run it
      con = controller.new

      #set conditional helper
      con.is_amf = true
      con.is_rubyamf = true
      con.rubyamf_params = rubyamf_params

      res = con.dispatch(method_name, req)

      #unset conditional helper
      con.is_amf = false
      con.is_rubyamf = false

      return con.amf_response
    end

    def get_service controller_name, method_name
      # Check controller and validate against hacking attempts
      begin
        raise "not controller" unless controller_name =~ /^[A-Za-z:]+Controller$/
        controller = ActiveSupport::Dependencies.ref(controller_name).get
        raise "not controller" unless controller.respond_to?(:controller_name) && controller.respond_to?(:action_methods)
      rescue Exception => e
        raise "Service #{controller_name} does not exist"
      end

      # Check action
      unless controller.action_methods.include?(method_name)
        raise "Service #{controller_name} does not respond to #{method_name}"
      end

      return controller
    end

    def build_params controller_name, method_name, args
      params = {}
      # args.each_with_index {|obj, i| params[i] = obj} Params added as an option
      params.merge!(@config.mapped_params(controller_name, method_name, args))
      params
    end
  end
end
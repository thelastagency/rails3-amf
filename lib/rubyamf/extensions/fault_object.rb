require 'rocketamf/values/messages'
require 'rubyamf/app/fault_object'

# This is the Rails 3+ version of the legacy FaultObject. Pretty much a HACK
FaultObject.class_eval do

  # Returns a RocketAMF::Values::ErrorMessage with the same values.
  def error_message request

    # Get the remoting message from the request
    request.env['rails3amf.request'].messages.each do |m|
      @remoting_message = m.data if m.data.is_a?(RocketAMF::Values::RemotingMessage)
    end

    if self['payload'] && self['payload'].is_a?(Exception)
      # This is not quite legacy behavior as it returns more info than before.
      msg = RocketAMF::Values::ErrorMessage.new(@remoting_message, self['payload'])
      msg.faultString = self['message'] if self['message']
      msg.extendedData = self['payload']
      msg
    else

      # Create an exception payload
      begin
        raise self['message']
      rescue Exception => e
        msg = RocketAMF::Values::ErrorMessage.new(@remoting_message, e)
        msg.instance_variable_set('@faultCode', 1)
        msg.instance_variable_set('@faultDetail', '')
        msg.instance_variable_set('@extendedData', self['payload'])
        msg
      end
    end
  end
end
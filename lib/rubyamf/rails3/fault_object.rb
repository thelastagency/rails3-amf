# This is the Rails 3+ version of the legacy FaultObject
class FaultObject < RocketAMF::Values::ErrorMessage

  def initialize message=nil, payload=nil
    super message
    #self._explicitType = 'flex.messaging.messages.ErrorMessage'

    if payload && payload.respond_to?(:backtrace)
      @e = payload
      @faultCode = @e.class.name
      @faultDetail = @e.backtrace.join("\n")
      @faultString = @e.message
      @rootCause = @e.backtrace[0]
      @extendedDate = @e.backtrace
    else
      @faultCode = 1
      @faultString = message
      @extendedData = payload
    end
  end
end
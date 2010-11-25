require 'rubyamf/rails3/rails3_configuration'

# Extend any ruby class with this method to register amf mappings in the class.
module RubyAMF
  module Configuration
    module Registration
      def register_amf(mapping)
         RubyAMF::Configuration::ClassMappings.register(mapping)
      end
    end
  end
end
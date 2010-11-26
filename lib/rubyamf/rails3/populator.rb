require 'rubyamf/rails3/rails3_configuration'
require 'rubyamf/util/vo_helper'

# Fully implements legacy mapping functionality. Likely rebuilding this will lead to better deserialization.
module RubyAMF
  module Populator
    class Base
      include RubyAMF::Configuration
      include RubyAMF::VoHelper

      def can_handle? obj
         true
      end

      def populate obj, props, dynamic_props

        # Translate case, if necessary
        if ClassMappings.translate_case
          props.each_pair { |key, value| VoUtil.set_value(obj, key.to_s.dup.to_snake!, value) } # need to do it this way because the key might be frozen
        else
          props.each_pair { |key, value| VoUtil.set_value(obj, key.to_s, value) }
        end

        VoUtil.finalize_object(obj)
        obj
      end
    end
  end
end
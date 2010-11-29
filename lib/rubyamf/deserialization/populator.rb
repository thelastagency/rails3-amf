require 'rubyamf/util/vo_helper'

# Fully implements legacy mapping functionality. Likely rebuilding this will lead to better deserialization.
module RubyAMF
  module Deserialization
    class Populator
      include RubyAMF::VoHelper

      class << self

        # Allows populator to be configured to translate case.
        def use_case_translation
          class_eval do
            def set_values(obj, props)
              props.each_pair { |key, value| VoUtil.set_value(obj, key.to_s.dup.to_snake!, value) } # need to do it this way because the key might be frozen
            end
          end
        end
      end

      def can_handle? obj
         true
      end

      def populate obj, props, dynamic_props

        set_values(obj, props)

        VoUtil.finalize_object(obj)
        obj
      end

      def set_values(obj, props)
        props.each_pair { |key, value| VoUtil.set_value(obj, key.to_s, value) }
      end
    end
  end
end
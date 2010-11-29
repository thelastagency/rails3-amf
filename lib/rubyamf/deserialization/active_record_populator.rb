require 'rubyamf/deserialization/populator'
require 'active_record'

module RubyAMF
  module Deserialization
    class ActiveRecordPopulator < RubyAMF::Deserialization::Populator

      def can_handle? obj
         obj.is_a?(ActiveRecord::Base)
      end
    end
  end
end

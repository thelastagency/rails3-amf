require 'active_record'

module RubyAMF
  module Populator
    class ActiveRecordPopulator < RubyAMF::Populator::Base

      def can_handle? obj
         obj.is_a?(ActiveRecord::Base)
      end
    end
  end
end

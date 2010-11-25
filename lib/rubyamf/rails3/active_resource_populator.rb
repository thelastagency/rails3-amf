require 'active_resource'

module RubyAMF
  module Populator
    class ActiveResourcePopulator < RubyAMF::Populator::Base

      def can_handle? obj
         obj.is_a?(ActiveResource::Base)
      end
    end
  end
end
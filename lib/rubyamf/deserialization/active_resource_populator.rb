require 'rubyamf/deserialization/populator'
require 'active_resource'

module RubyAMF
  module Deserialization
    class ActiveResourcePopulator < RubyAMF::Deserialization::Populator

      def can_handle? obj
         obj.is_a?(ActiveResource::Base)
      end
    end
  end
end
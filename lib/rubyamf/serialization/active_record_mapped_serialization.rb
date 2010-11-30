require 'rubyamf/serialization/mapped_serialization'

module RubyAMF
  module Serialization
    class ActiveRecordMappedSerialization < RubyAMF::Serialization::MappedSerialization

      private
      # Updates included associations from the map
      def serialize_mapped_properties(map, local_options, include_associations, options)

        # Add any associations from mapping. Ignore if asscociations included in original options.
        if include_associations.nil? && map[:include]
          include_associations = map[:include]
          options[:rubyamf_ignore_check_for_associations] = true # Flag so we don't check for associations if they are mapped
        end
        super
      end
    end
  end
end
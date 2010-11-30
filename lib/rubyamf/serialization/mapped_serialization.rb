require 'rubyamf/serialization/serialization'

module RubyAMF
  module MappedSerialization

   # Serializes properties and translates case if necessary
    def serialize_properties options, include_associations

      # Apply mappings to object as long as no options were passed in already and the object has mapped properties
      if ClassMappings.use_mapped_serialization_for_ruby_class(class_name = self.class.name) && !(options[:only] || options[:except] || options[:methods])

        # Retrieve map, which contains scoped attributes and associations
        map = ClassMappings.get_vo_mapping_for_ruby_class(class_name)

        # Clone the options so the modified options do not pass to associations being serialized
        serialize_mapped_properities(map, options.clone, include_associations, options)
      else
        super options, include_associations
      end
    end

    private

    # Returns
    def serialize_mapped_properities(map, local_options, include_associations, options)

      # Add any methods from mapping.
      local_options[:methods] = map[:methods]

      # Add mapped included attributes.
      local_options[:only] = map[:only]

      # Add mapped excluded attributes.
      local_options[:except] = map[:except]

      super local_options
    end
  end
end
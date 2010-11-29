module RocketAMF
  ClassMapping.class_eval do

    # Allows a specfic mapping to be cleared in the RocketAMF::ClassMapper so that in-class mapping clears and resets in
    # development and testing environments.
    def clear_mapping(ruby_class_name)
      ruby_map = @mappings.instance_variable_get('@ruby_mappings')
      @mappings.instance_variable_get('@as_mappings').delete(ruby_map[ruby_class_name])
      ruby_map.delete(ruby_class_name)
    end
  end
end
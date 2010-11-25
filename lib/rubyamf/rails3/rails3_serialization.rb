require 'rails3-amf/serialization'
require 'rails3-amf/intermediate_model'
require 'rubyamf/rails3/rails3_configuration'
require 'rubyamf/util/vo_helper'
require 'active_record'

module Rails3AMF
  Serialization.module_eval do
    include RubyAMF::Configuration
    include RubyAMF::VoHelper

    # Control the serialization of the model by specifying the relations, properties,
    # methods, and other data to serialize with the model. Parameters take the
    # same form as serializable_hash - see active record/active model serialization
    # for more details.
    #
    # If not serialized to an intermediate form before it reaches the AMF
    # serializer, it will be serialized with the default options.
    def to_amf options=nil
      options ||= {}

      # Remove associations so that we can call to_amf on them separately
      include_associations = options.delete(:include) if options[:include]

      # Get the class name for accessing mapping functionality
      class_name = self.class.name

      # Using ClassMappings.assume_types or if if no attribute, method or association mappings are set,
      # mapped serialization is skipped.
      if ClassMappings.use_mapped_serialization_for_ruby_class(class_name)

        # Retrieve map, which contains scoped attributes and associations
        map = ClassMappings.get_vo_mapping_for_ruby_class(class_name)

        # Merge any associations from mapping.
        include_associations ||= []
        if map[:include]
          include_associations |= map[:include]
        elsif self.is_a?(ActiveRecord::Base) && ClassMappings.check_for_associations
          check_for_associations(include_associations) #Add eager loaded associations not included yet
        end

        # Modify local options so that only originally specified options pass to associations in
        # serializable_add_includes, while modified mapped options pass to serializable_hash.
        local_options = options.dup || {}

        # Merge any methods from mapping.
        if map[:methods]
          local_options[:methods] ||= []
          local_options[:methods] |= map[:methods]
        end

        # Merge mapped included attributes.
        if map[:only]
          local_options[:only] ||= []
          local_options[:only] |= map[:only]
        end

        # Merge mapped excluded attributes.
        if map[:except]
          local_options[:except] ||= []
          local_options[:except] |= map[:except]
        end

      else
        local_options = options
        if self.is_a?(ActiveRecord::Base) && ClassMappings.check_for_associations
          include_associations ||= []
          check_for_associations(include_associations) #Add eager loaded associations not included yet
        end
      end

      # Create props hash and serialize relations if supported method available. Handles all attributes and methods.
      props = serializable_hash(local_options)

      # Translate case
      props = props.keys.inject({}) do |camel_cased_props, key|
        camel_cased_props[key.to_s.dup.to_camel!] = props[key] # Need to do this in case key is frozen
        camel_cased_props
      end if ClassMappings.translate_case

      # Process associations and translate case
      if !include_associations.empty?
        options[:include] = include_associations
        send(:serializable_add_includes, options) do |association, records, opts|
          props[ClassMappings.translate_case ? association.to_s.dup.to_camel! : association] = records.is_a?(Enumerable) ? records.map { |r| r.to_amf(opts) } : records.to_amf(opts)
        end
      end

      # Create wrapper and return
      Rails3AMF::IntermediateModel.new(self, props)
    end

    private

    # Returns array of all loaded association name symbols.
    def check_for_associations(include_associations)
      return if (reflections = self.class.reflections).empty?

      # Add any association instances not in include_associations
      reflections.each do |reflection|
        name = reflection[0]
        include_associations << name if self.instance_variable_get("@#{name}") && !include_associations.include?(name)
      end
    end
  end
end
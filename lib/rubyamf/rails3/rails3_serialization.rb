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
    #
    # If options are set, other than scope, they override all mappings.
    def to_amf options=nil

      # Remove associations so that we can call to_amf on them separately
      include_associations = options.delete(:include) unless options.nil?

      # Apply mappings to object.
      if ClassMappings.use_mapped_serialization_for_ruby_class(class_name = self.class.name)

        # If any options other than scope are specified, we skip any mapping for them and defer to those options.
        # We let classes that normally would be mapped take the performance hit on serialization over those that
        # specify no mapping options other than :as or :actionscript and :ruby classes so that they map the fastest.
        # This is a philosophical question, but the base is fastest performance for the least constricted objects.
        unless include_associations || options[:only] || options[:except] || options[:methods]

          # Retrieve map, which contains scoped attributes and associations
          map = ClassMappings.get_vo_mapping_for_ruby_class(class_name)

          # Add any associations from mapping.
          if map[:include]
            include_associations = map[:include]
          elsif self.is_a?(ActiveRecord::Base) && ClassMappings.check_for_associations
            include_associations = []
            check_for_associations(include_associations) #Include eager loaded associations
          end

          # Use local options for serializable_hash that don't pass to associations in serializable_add_includes
          # since they only apply to this object.
          local_options = {}

          # Add any methods from mapping.
          local_options[:methods] = map[:methods]

          # Add mapped included attributes.
          local_options[:only] = map[:only]

          # Add mapped excluded attributes.
          local_options[:except] = map[:except]

          mapped = true
        end
      end

      # If not mapped, we need to set local options to initial options and still check for associations.
      unless mapped
        local_options = options
        if self.is_a?(ActiveRecord::Base) && ClassMappings.check_for_associations
          include_associations ||= []
          check_for_associations(include_associations) #Include eager loaded associations
        end
      end

      # Create props hash and serialize relations if supported method available. Handles all attributes and methods.
      props = serializable_hash(local_options)

      # Translate case on properties. Use to_s in case :methods are specified which can be symbols and return as such.
      # All other attribute keys are returned as strings already. A faster option may be to collect methods as strings
      # before passing them to serializable_hash.
      props = props.keys.inject({}) do |camel_cased_props, key|
        camel_cased_props[key.to_s.dup.to_camel!] = props[key] # Need dup in case key is frozen.
        camel_cased_props
      end if ClassMappings.translate_case

      # Process associations and translate case
      if include_associations
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

      # Add any association instances not in include_associations. Optional approach is to get all reflection
      # names and merge them with include_associations, but I suspect this is faster.
      reflections.each do |reflection|
        name = reflection[0]
        include_associations << name if self.instance_variable_get("@#{name}") && !include_associations.include?(name)
      end
      include_associations = nil if include_associations.empty?
    end
  end
end
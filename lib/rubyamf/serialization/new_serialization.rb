require 'rubyamf/extensions/configuration'
require 'rails3-amf/intermediate_model'
require 'active_model'
require 'active_record'

# Defines the base serialization of any object that includes this module.
module RubyAMF
  module Serialization
    include RubyAMF::Configuration

    # Control the serialization of the model by specifying the relations, properties,
    # methods, and other data to serialize with the model. Parameters take the
    # same form as serializable_hash - see active record/active model serialization
    # for more details.
    #
    # If not serialized to an intermediate form before it reaches the AMF
    # serializer, it will be serialized with the default options.
    #
    # If mapping options are not specified that affect serialization, this is the serializer used.
    def to_amf options=nil
      options ||= {}

      # Remove associations so that we can call to_amf on them seperately
      include_associations = options.delete(:include) unless options.empty?

      # Create props hash and serialize relations if supported method available.
      props = serialize_properties(options, include_associations)

      # Serialize associations separately
      serialize_associations(include_associations, options, props)

      Rails3AMF::IntermediateModel.new(self, props)
    end

    # Called by serialization routines if the user did not use to_amf to convert
    # to an intermediate form prior to serialization. Encodes using the default
    # serialization settings.
    def encode_amf serializer
      self.to_amf.encode_amf serializer
    end

    private

    # Utility method that returns array of all loaded association name symbols.
    def check_for_associations(include_associations)
      return if (reflections = self.class.reflections).empty?
      include_associations ||= []

      # Add any association instances not in include_associations. Optional approach is to get all reflection
      # names and merge them with include_associations, but I suspect this is faster.
      reflections.each do |reflection|
        name = reflection[0]
        include_associations << name if self.instance_variable_get("@#{name}") && !include_associations.include?(name)
      end
      include_associations = nil if include_associations.empty?
    end

    # Serializes associations separately
    def serialize_associations(include_associations, options, props)
      if self.is_a?(ActiveRecord::Base) && ClassMappings.check_for_associations
        options[:rubyamf_ignore_check_for_associations] ? options.delete(:rubyamf_ignore_check_for_associations) : check_for_associations(include_associations) 
      end
      if include_associations
        options[:include] = include_associations

        # The following is not DRY, but better performance
        if ClassMappings.translate_case
          send(:serializable_add_includes, options) do |association, records, opts|
            props[association.to_s.dup.to_camel!] = records.is_a?(Enumerable) ? records.map { |r| r.to_amf(opts) } : records.to_amf(opts)
          end
        else
          send(:serializable_add_includes, options) do |association, records, opts|
            props[association] = records.is_a?(Enumerable) ? records.map { |r| r.to_amf(opts) } : records.to_amf(opts)
          end
        end
      end
    end

    # Serializes properties
    def serialize_properties(options, include_associations)
      if ClassMappings.translate_case
        serializable_hash(options).inject({}) do |camel_cased_props, key|
            camel_cased_props[key.to_s.dup.to_camel!] = props[key] # Need dup in case key is frozen.
            camel_cased_props
          end
      else
        serializable_hash(options)
      end
    end
  end

  # Serialization that is included in classes that map more than the class relationships
  module MappedSerialization
    include Serialization

    alias_method :old_serialize_properties, :serialize_properties

    # Serializes properties and translates case if necessary
    def serialize_properties options, include_associations

      # Apply mappings to object as long as no options were passed in already and the object has mapped properties
      if ClassMappings.use_mapped_serialization_for_ruby_class(class_name = self.class.name) && !(options[:only] || options[:except] || options[:methods])

        # Retrieve map, which contains scoped attributes and associations
        map = ClassMappings.get_vo_mapping_for_ruby_class(class_name)

        # Clone the options so the modified options do not pass to associations being serialized
        serialize_mapped_properties(map, options.clone, include_associations, options)
      else
        old_serialize_properties options, include_associations
      end
    end

    private

    # Returns
    def serialize_mapped_properties(map, local_options, include_associations, options)

      # Add any methods from mapping.
      local_options[:methods] = map[:methods]

      # Add mapped included attributes.
      local_options[:only] = map[:only]

      # Add mapped excluded attributes.
      local_options[:except] = map[:except]

      old_serialize_properties local_options, include_associations
    end
  end

  # Serialization that is included in ActiveRecords that map more than the class relationships
  module ActiveRecordMappedSerialization
    include MappedSerialization
    
    alias_method :old_serialize_mapped_properties, :serialize_mapped_properties

    private
    # Updates included associations from the map
    def serialize_mapped_properties(map, local_options, include_associations, options)

      # Add any associations from mapping. Ignore if asscociations included in original options.
      if include_associations.nil? && map[:include]
        include_associations = map[:include]
        options[:rubyamf_ignore_check_for_associations] = true # Flag so we don't check for associations if they are mapped
      end
      old_serialize_mapped_properties(map, local_options, include_associations, options)
    end
  end
end

# Hook into any object that includes ActiveModel::Serialization
module ActiveModel::Serialization
  include RubyAMF::Serialization
end

# Make ActiveSupport times serialize properly
class ActiveSupport::TimeWithZone
  def encode_amf serializer
    serializer.serialize self.to_datetime
  end
end
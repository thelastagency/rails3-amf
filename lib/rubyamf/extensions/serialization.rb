require 'rubyamf/extensions/configuration'
require 'rails3-amf/intermediate_model'
require 'active_model'
require 'active_record'

# Defines the serialization of any class that includes this module, including any classes that include
# ActiveModel::Serialization. This module is configured to automatically set all serialization options to be the
# very fastest possible for each class individually. Every class that directly or indirectly includes this module is
# only configured for options that apply to it. E.g., if the class is not an ActiveRecord , no association related
# methods are included or called on the class.
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
    def to_amf options=nil
      options ||= {}

      # Create props hash and serialize relations if supported method available
      props = serialize_properties(options)

      Rails3AMF::IntermediateModel.new(self, props)
    end

    # Called by serialization routines if the user did not use to_amf to convert
    # to an intermediate form prior to serialization. Encodes using the default
    # serialization settings.
    def encode_amf serializer
      self.to_amf.encode_amf serializer
    end

    private

    # Serializes properties and is a hook for modifiying serialized properties
    def serialize_properties(options, include_associations=nil)
      return serializable_hash(options), include_associations
    end

    # Contains methods to configure a class for serialization
    module Configuration
      include RubyAMF::Configuration

      # Automatically sets all the configuration options when included in a class.
      def configure_rubyamf_serialization
        if is_active_record = self.ancestors.include?(ActiveRecord::Base)
          self.use_active_record_serialization
          self.use_case_translation if ClassMappings.translate_case # Must set this before configuring check_for_associations
          self.use_check_for_associations if ClassMappings.check_for_associations
        else
          self.use_case_translation if ClassMappings.translate_case
        end
        if ClassMappings.use_mapped_serialization_for_ruby_class(self.name)
          self.use_mapped_serialization
          self.use_mapped_active_record_serialization if is_active_record
        end
      end

      # Updates class to check for eager loaded associations on ActiveRecords
      def use_active_record_serialization

        # Activate checking for associations
        self.class_eval do

          # Only ActiveRecords have associations, so we add functionality to serialize associations
          def to_amf options=nil
            options ||= {}

            # Remove associations so that we can call to_amf on them seperately
            include_associations = options.delete(:include) unless options.empty?

            # Create props hash and serialize relations if supported method available. Pass in include associations
            # to pick up included associations.
            props, include_associations = serialize_properties(options, include_associations)

            # Serialize associations separately
            serialize_associations(include_associations, options, props)

            Rails3AMF::IntermediateModel.new(self, props)
          end

          # Serializes associations separately
          def serialize_associations(include_associations, options, props)
            if include_associations
              options[:include] = include_associations
              send(:serializable_add_includes, options) do |association, records, opts|
                props[association] = records.is_a?(Enumerable) ? records.map { |r| r.to_amf(opts) } : records.to_amf(opts) # Need dup in case association key is frozen.
              end
            end
          end
        end
      end

      # Updates class to use case translation
      def use_case_translation(is_active_record=false)

        # Update for associations
        self.class_eval do
          def serialize_associations(include_associations, options, props)
            if include_associations
              options[:include] = include_associations
              send(:serializable_add_includes, options) do |association, records, opts|
                props[association.to_s.dup.to_camel!] = records.is_a?(Enumerable) ? records.map { |r| r.to_amf(opts) } : records.to_amf(opts) # Need dup in case association key is frozen.
              end
            end
          end
        end if is_active_record

        # Update for properties
        self.class_eval do
          def serialize_properties options, include_associations
            props = serializable_hash(options)
            camel_cased_props = {}
            props.each { |k, v| camel_cased_props[k.to_s.dup.to_camel!] = v } # Need to_s in case key is a symbol. Need dup in case key is frozen.
            return camel_cased_props, include_associations
          end
        end
      end

      # Updates class to check for eager loaded associations on ActiveRecords
      def use_check_for_associations

        # Activate checking for associations
        self.class_eval do
          alias_method :old_serialize_associations, :serialize_associations

          private
          
          def serialize_associations(include_associations, options, props)
            check_for_associations(include_associations, options)
            old_serialize_associations(include_associations, options, props)
          end

          # Utility method that returns array of all loaded association name symbols. It is included if
          # ClassMappings.check_for_case is true.
          def check_for_associations(include_associations, options)
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
        end
      end

      # Updates use mapped serialization
      def use_mapped_serialization
        self.class_eval do
          alias_method :old_serialize_properties, :serialize_properties

          private

          # Serializes properties and translates case if necessary
          def serialize_properties options, include_associations

            # Apply mappings to object as long as no options were passed in already and the object has mapped properties
            if ClassMappings.use_mapped_serialization_for_ruby_class(class_name = self.class.name) && !(options[:only] || options[:except] || options[:methods])

              # Retrieve map, which contains scoped attributes and associations
              map = ClassMappings.get_serialization_mapping_for_ruby_class(class_name)

              # Clone the options so the modified options do not pass to associations being serialized
              serialize_mapped_properties(map, options.clone, include_associations, options)
            else
              old_serialize_properties options, include_associations
            end
          end

          # Returns
          def serialize_mapped_properties(map, local_options, include_associations, options)

            # Add any methods from mapping.
            local_options[:methods] = map[:methods] if map[:methods]

            # Add mapped included attributes.
            local_options[:only] = map[:only] if map[:only]

            # Add mapped excluded attributes.
            local_options[:except] = map[:except] if map[:except]

            old_serialize_properties local_options, include_associations
          end
        end
      end
      
      # Updates class to use mapped active record serialization
      def use_mapped_active_record_serialization
        self.class_eval do
          alias_method :old_check_for_associations, :check_for_associations
          alias_method :old_serialize_mapped_properties, :serialize_mapped_properties

          private

          def check_for_associations(include_associations, options)
            if options[:rubyamf_ignore_check_for_associations]
              options.delete(:rubyamf_ignore_check_for_associations) # Only relevant to the current instance
              return
            end
            old_check_for_associations(include_associations, options)
          end

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
    end

    # Extend configuration methods to the base class. This method automagically configures a class for serialization.
    def self.included(base)
      if base.is_a?(Class)
        base.extend Configuration
        base.configure_rubyamf_serialization
      else

        # Here we set a mock to_amf method to update a class if it has not been configured for serialization.
        # This makes sure classes in development and testing mode are configured based on the system settings when
        # the classes reload. Further, any custom class that includes ActiveModel::Serialization gets all the
        # functionality as well. This only configures a class the first time one of its instances is serialized.
        base.module_eval do
          def to_amf options=nil
            self.class.class_eval do
              include Serialization
            end
            self.to_amf options
          end
        end
      end
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
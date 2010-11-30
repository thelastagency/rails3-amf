require 'rubyamf/extensions/configuration'
require 'rocketamf/class_mapping'
require 'rubyamf/util/vo_helper'
require 'active_model'
require 'active_record'
require 'active_resource'

# Defines the deserialization of any class that includes this module, including any classes that include
# ActiveModel::Serialization. This module is configured to automatically set all deserialization options to be the
# very fastest possible for each class individually. Every class that directly or indirectly includes this module is
# only configured for options that apply to it. E.g., if the class is not an ActiveRecord , no association related
# methods are included or called on the class.
module RubyAMF
  module Deserialization
    include RubyAMF::Configuration
    include RubyAMF::VoHelper

    # Custom populator that is injected into RocketAMF that controls all the mapped deserialization. If
    # no mapping is configured, it defaults RocketAMF fallback serialization.
    class Populator

      def can_handle? obj
         obj.respond_to?(:rubyamf_populate)
      end

      def populate obj, props, dynamic_props
        obj.rubyamf_populate props, dynamic_props
      end
    end

    # Control the deserialization of the model by specifying the relations, properties,
    # methods, and other data to deserialize with the model.
    def rubyamf_populate props, dynamic_props
      set_props(props, dynamic_props)
      self
    end

    private
    # Sets the attributes of the object. This is the RocketAMF fallback code.
    def set_props(props, dynamic_props)
      props.merge! dynamic_props if dynamic_props
      hash_like = self.respond_to?("[]=")
      props.each do |key, value|
        if self.respond_to?("#{key}=")
          self.send("#{key}=", value)
        elsif hash_like
          self[key.to_sym] = value
        end
      end
    end

    # Contains methods to configure a class for deserialization
    module Configuration
      include RubyAMF::Configuration

      # Automatically sets all the configuration options when included in a class.
      def configure_rubyamf_deserialization
        if true || self.ancestors.include?(ActiveRecord::Base) #Currently legacy rubyamf deserialization deserializes all types until.
          self.use_active_record_deserialization
        elsif self.ancestors.include?(ActiveResource::Base)
          self.use_active_resource_deserialization
        end
        self.use_case_translation if ClassMappings.translate_case

        # if ClassMappings.use_mapped_serialization_for_ruby_class(self.name)
          # Do nothing now. Uses legacy rubyamf deserialization if an ActiveRecord or ActiveResource
        # end
      end

      # Updates class to deserialize ActiveRecords
      def use_active_record_deserialization

        # Activate active record deserialization
        self.class_eval do
          def rubyamf_populate props, dynamic_props
            set_props(props, dynamic_props)
            VoUtil.finalize_object(self)
            self
          end
        end

        # Set the properties
        self.class_eval do
          def set_props(props, dynamic_props)
            props.each_pair { |key, value| VoUtil.set_value(self, key.to_s, value) }
          end
        end
      end

      # Updates class to deserialize ActiveResources
      def use_active_resource_deserialization
        use_active_record_deserialization # Same for now
      end

      # Updates class to use case translation
      def use_case_translation
        if true # self.ancestors.include?(ActiveRecord::Base) || self.ancestors.include?(ActiveResource::Base) Currently all types deserialized using legacy property population.
           self.class_eval do
             def set_props(props, dynamic_props)
                props.each_pair { |key, value| VoUtil.set_value(self, key.to_s.dup.to_snake!, value) } # need to do it this way because the key might be frozen
              end
           end
        else
          self.class_eval do
            # Sets the attributes of the object
            def set_props(props, dynamic_props)
              props.merge! dynamic_props if dynamic_props
              hash_like = self.respond_to?("[]=")
              props.each do |key, value|
                key = key.to_s.dup.to_snake! # need to do it this way because the key might be frozen
                if self.respond_to?("#{key}=")
                  self.send("#{key}=", value)
                elsif hash_like
                  self[key.to_sym] = value
                end
              end
            end
          end
        end
      end

      # Updates use mapped serialization
      def use_mapped_serialization
        # Do nothing until implemented. Handled in legacy rubyamf.
      end
      
      # Updates class to use mapped active record serialization
      def use_mapped_active_record_serialization
        # Do nothing until implemented. Handled in legacy rubyamf.
      end
    end

    # Extend configuration methods to the base class. This method automagically configures a class for deserialization.
    def self.included(base)
      if base.is_a?(Class)
        base.extend Configuration
        base.configure_rubyamf_deserialization
      else

        # Here we set a mock populate method to update a class if it has not already been configured for
        # deserialization. This makes sure classes in development and testing mode are configured based on the system
        # settings when the classes reload. Further, any custom class that includes ActiveModel::Serialization gets all
        # the functionality as well. This only configures a class the first time one of its instances is serialized.
        base.module_eval do
          def rubyamf_populate props, dynamic_props
            self.class.class_eval do
              include Deserialization
            end
            self.rubyamf_populate props, dynamic_props
          end
        end
      end
    end
  end
end

# Load the populator into RocketAMF
RocketAMF::ClassMapper.object_populators << RubyAMF::Deserialization::Populator.new

# Hook into any object that includes ActiveModel::Serialization. This is not really the purest way to do things,
# but it is the simplest to make sure the method populate is an instance method on objects that include
# ActiveModel::Serialization
module ActiveModel::Serialization
  include RubyAMF::Deserialization
end
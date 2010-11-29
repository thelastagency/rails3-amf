require 'rubyamf/app/configuration'
require 'rubyamf/deserialization/populator'
require 'rubyamf/deserialization/active_record_populator'
require 'rubyamf/deserialization/active_resource_populator'
require 'rubyamf/serialization'
require 'active_record'
require 'active_resource'

require 'rails3-amf/configuration'
require 'rocketamf/pure/serializer'
require 'rocketamf/pure/deserializer'

#The only modifications to the original configuration.rb file was to comment out require and include statements
#which you can find by searching on fosrias in legacy_configuration.rb, which is the original configuration file. Any
#other references to fosrias are previous patch tags in the file.
module RubyAMF
  module Configuration

    # Module to be included for in-class mapping. In-class mapping registers the first time a class loads and thus
    # is automatically picked up by regular deserialization and also by using assume_types since in either case, the
    # first step is to create an new object. Thus, the first time the class loads it registers and configures both
    # deserialization and serialization options.
    module Registration
      def register_amf(mapping)

         # Short cut for in-class mapping. :ruby not necessary
         mapping[:ruby] = ruby_class_name = self.name

         # Actionscript mapping not necessary if assume_types is true.
         if !(mapping[:as] || mapping[:actionscript]) && ClassMappings.assume_types
           mapping[:actionscript] = ruby_class_name
         end

         raise "ActionScript class is not mapped in #{self.class.name}." if !(mapping[:as] || mapping[:actionscript])

         # Register the mapping
         ClassMappings.register(mapping)
      end
    end

    # Deserialization flags
    @has_active_record = false
    @has_active_resource = false
    @has_custom = false

    # Opens the legacy class to implement Rails 3 and RocketAMF mapping functionality.
    ClassMappings.class_eval do
      extend RubyAMF::Serialization

      class << self

        alias old_register register

        # Adds assume types
        def assume_types value
          super.assume_types = value
          Rails3AMF::Configuration.auto_class_mapping = value
        end

        # Clears the mapping for a particular class.
        def clear_mapping(ruby_class_name)
          if map = @class_mappings_by_ruby_class.delete(ruby_class_name)
            @scoped_class_mappings_by_ruby_class.delete(ruby_class_name)
            @class_mappings_by_actionscript_class.delete(map[:actionscript])

            # Clear in RocketAMF
            RocketAMF::ClassMapper.clear_mapping(ruby_class_name)
          end
        end

        #Overrides legacy register to synchronize mapping with RocketAMF
        def register(mapping)

          # Allow RocketAMF mapping symbols
          mapping[:actionscript] = mapping[:as] if mapping[:as] && !mapping[:actionscript]

          #Clear first so that changes in in-class model mapping definitions are set correctly in dev and test mode
          clear_mapping(mapping[:ruby])

          # Register the mapping in the legacy map
          old_register(mapping)

          # Convert legacy maps to Rails 3+ maps
          if mapping[:attributes] && !(mapping[:only] || mapping[:except])
            mapping[:only] = mapping[:attributes]
          elsif mapping[:attributes]
            raise "Mapping Error for #{mapping[:ruby]}: Do not specify :attributes and :only or :except. Use either :attributes or :only or :except."
          end

          if mapping[:associations] && !mapping[:include]
            mapping[:include] = mapping[:associations]
          elsif mapping[:associations]
            raise "Mapping Error for #{mapping[:ruby]}: Do not specify :associations and :include. Use either :associations or :include"
          end

          # Convert strings to symbols since reflection in serializer uses symbols
          if mapping[:include] && mapping[:include].is_a?(Hash)
            mapping[:include].each_key do |k|
              mapping[:include][k].collect! { |item| item.to_sym }
            end
          elsif mapping[:include]
            mapping[:include].collect! { |item| item.to_sym }
          end

          # Check if we have set any attributes, associations or methods. If not, we can use faster serialization
          # by bypassing mapping implementation in serializers
          if mapping[:include] || mapping[:exclude] || mapping[:only] || mapping[:method]
            mapping[:use_mapped_serialization] = true
          else
            mapping[:use_mapped_serialization] = false
          end

          # Register the class in RocketAMF
          if (mapping[:ruby] && mapping[:actionscript])

            # Register the mapping in the serializer/deserializer
            RocketAMF::ClassMapper.define do |m|
              m.map :as => mapping[:actionscript] ||= mapping[:as], :ruby => mapping[:ruby]
            end
          else
            raise "Mapping Error. :ruby and :actionscript or :as must be mapped"
          end

          # Configure deserialization and serialization
          ruby_class = mapping[:ruby].split('::').inject(Kernel) {|scope, const_name| scope.const_get(const_name)} #eval(mapping[:ruby])
          has_mapped_serialization = mapping[:use_mapped_serialization]

          # Configure the application's Deserialization and Serialization flags
          if ruby_class.ancestors.include?(ActiveRecord::Base)
            populator_class_name = "RubyAMF::Deserialization::ActiveRecordPopulator" unless @has_active_record #Only add the populator once
            @has_active_record = true

          elsif ruby_class.ancestors.include?(ActiveResource::Base)
            populator_class_name =  "RubyAMF::Deserialization::ActiveResourcePopulator" unless @has_active_resource #Only add the populator once
            @has_active_resource = true

          else
            populator_class_name =  "RubyAMF::Deserialization::Populator" unless @has_custom  #Only add the populator once
            @has_custom = true
          end

          # Include serialization methods in the class when it is registered. In production mode, this ensures
          # all registered classes have their serialization properties set. In development and testing mode,
          # this also resets serialization for the classes that have in-class mappings. All other classes registered
          # in rubyamf_config.rb or picked up by assume_types are configured by the serialization included in
          # RubyAMF::Serialization included in ActiveRecord::Serialization.
            ruby_class.class_eval do
              include RubyAMF::Serialization
            end

          # Configure deserialization
          if populator_class_name
            populator_class = eval(populator_class_name)
            populator_class.use_case_translation if translate_case
            if populator_class
              if ruby_class.is_a?(ActiveRecord::Base)
                # Always put active record populator at the top
                RocketAMF::ClassMapper.object_populators.unshift(populator_class.new)
              else
                RocketAMF::ClassMapper.object_populators << populator_class.new
              end
            end
          end
        end

        # Registers mappings for each class.
        def register_by_class_names(ruby_class_names)
          ruby_class_names.each do |ruby_class_name|
            ruby_class = eval(ruby_class_name) #ruby_class_name.split('::').inject(Kernel) {|scope, const_name| scope.const_get(mapping[:ruby])}
            if !ruby_class
              raise "Attempting to register a class that does not exist: #{ruby_class_name}."
            end
          end
        end

        # Checks if mapping is used on a model. Optimizes deserialization if mapping not used on a particular object.
        def use_mapped_serialization_for_ruby_class(ruby_class)
          return unless map = @class_mappings_by_ruby_class[ruby_class]
          map[:use_mapped_serialization]
        end

        # Legacy functionality translated for Rails 3 serializable_hash serialization functionality. Might get
        # a slight performance kick by using an if statement to check if :only specified vs. :exclude, but could run in
        # to scoping issues where some scope excludes some included attribute. Also, would be easy to add scoping
        # to methods, but at the cost of an extra set of steps below and I am not sure of the benefit at the
        # expense.
        def get_vo_mapping_for_ruby_class(ruby_class)
          return unless scoped_class_mapping = @scoped_class_mappings_by_ruby_class[ruby_class] # just in case they didnt specify a ClassMapping for this Ruby Class
          scoped_class_mapping[@current_mapping_scope] ||= (if vo_mapping = @class_mappings_by_ruby_class[ruby_class]
              vo_mapping = vo_mapping.dup # need to duplicate it or else we will overwrite the keys from the original mappings
              vo_mapping[:except]  = vo_mapping[:except][@current_mapping_scope]||[]  if vo_mapping[:except].is_a?(Hash)  # don't exclude any of these attributes if there is no scope
              vo_mapping[:only]    = vo_mapping[:only][@current_mapping_scope]||[]    if vo_mapping[:only].is_a?(Hash)    # don't include any of these attributes if there is no scope
              vo_mapping[:include] = vo_mapping[:include][@current_mapping_scope]||[] if vo_mapping[:include].is_a?(Hash) # don't include any of these associations if there is no scope.
              vo_mapping
            end
          )
        end
      end
    end
  end
end

# Add ability to map in the models.
module ActiveRecord
  Base.class_eval do
    extend RubyAMF::Configuration::Registration
  end
end

module ActiveResource
  Base.class_eval do
    extend RubyAMF::Configuration::Registration
  end
end

# Extend deserialization and serialization options
module RocketAMF
  # If we use array collections, we override how arrays are written.
  Pure::AMF3Serializer.class_eval do
    def write_array array
        write_object array, nil, {:class_name => 'flex.messaging.io.ArrayCollection', :members => [], :externalizable => true, :dynamic => false}
    end
  end if RubyAMF::Configuration::ClassMappings.use_array_collection

  # If we use ruby date time, we override how time objects are deserialized
  Pure::AMF3Deserializer.class_eval do
    # Do something here
  end if RubyAMF::Configuration::ClassMappings.use_ruby_date_time
end
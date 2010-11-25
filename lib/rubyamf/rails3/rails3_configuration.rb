require 'rubyamf/app/configuration'
require 'rubyamf/rails3/populator'
require 'rubyamf/rails3/active_record_populator'
require 'rubyamf/rails3/active_resource_populator'
require 'rubyamf/rails3/registration'
require 'rubyamf/util/string'
require 'active_record'
require 'active_resource'

require 'rails3-amf/configuration'

#The only modifications to the original configuration.rb file was to comment out require and include statements
#which you can find by searching on fosrias in legacy_configuration.rb, which is the original configuration file. Any
#other references to fosrias are previous
#patch tags in the file.
module RubyAMF
  module Configuration
    ClassMappings.class_eval do

      @has_active_record_populator = false
      @has_active_resource_populator = false
      @has_base_populator = false

      class << self

        alias old_register register

        #Overrides legacy register to synchronize mapping with RocketAMF
        def register(mapping)

          # Allow RocketAMF mapping symbols
          mapping[:actionscript] = mapping[:as] if mapping[:as] && !mapping[:actionscript]

          # Convert legacy maps to Rails 3 maps
          if mapping[:attributes] && !(mapping[:only] || mapping[:only])
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

          # Check if we have set any attributes, associations or methods. If not, we can use fast mapping
          if (mapping[:include] || mapping[:exclude] || mapping[:only] || mapping[:method])
            mapping[:use_mapped_serialization] = true
          else
            mapping[:use_mapped_serialization] = false
          end

          # Register the mapping in the legacy map
          old_register(mapping)

          # Register the class in RocketAMF and add associated populator
          if (mapping[:ruby] && mapping[:actionscript])

            # Register the mapping in the serializer/deserializer
            RocketAMF::ClassMapper.define do |m|
              m.map :as => mapping[:actionscript] ||= mapping[:as], :ruby => mapping[:ruby]
            end

            # Register related populators.
            if (mapping[:type] == 'active_record' || eval(mapping[:ruby]).is_a?(ActiveRecord::Base)) && !@has_active_record_populator #Only add the populator once
              mapping[:type] = 'active_record' # Do this in case not specified so populator loads
              populator_class_name = "RubyAMF::Populator::ActiveRecordPopulator"
              @has_active_record_populator = true

            elsif (mapping[:type] == 'active_resource' || eval(mapping[:ruby]).is_a?(ActiveResource::Base)) && !@has_active_resource_populator #Only add the populator once

              populator_class_name =  "RubyAMF::Populator::ActiveResourcePopulator"
              @has_active_resource_populator = true

            elsif mapping[:type] == 'custom' && !@has_base_populator #Only add the populator once

              populator_class_name =  "RubyAMF::Populator::Base"
              @has_base_populator = true
            end

            if populator_class_name
              populator_class = populator_class_name.split('::').inject(Kernel) {|scope, const_name| scope.const_get(const_name)}
              if populator_class
                if mapping[:type] == 'active_record'
                  # Always put active record populator at the top
                  RocketAMF::ClassMapper.object_populators.unshift(populator_class.new)
                else
                  RocketAMF::ClassMapper.object_populators << populator_class.new
                end
              end
            end
          else
            raise "Mapping Error. :ruby and :actionscript or :as must be mapped"
          end
        end

        #Registers classes as an array of class names by fully qualified package that have amf mappings registered
        #in the class. Ideally, loaded classes auto-register and thus is unnecessary.
        def register_by_class_names(ruby_class_names)

          #Load each class so that it maps itself if mappings are defined in it.
          ruby_class_names.each do |ruby_class_name|
            ruby_class = ruby_class_name.split('::').inject(Kernel) {|scope, const_name| scope.const_get(const_name)}
            if !ruby_class
              raise "Attempting to register a class that does not exist: #{ruby_class_name}."
            end
          end
        end

        # Optimizes deserialization if mapping not used.
        def use_mapped_serialization_for_ruby_class(ruby_class)
          return unless map = @class_mappings_by_ruby_class[ruby_class]
          map[:use_mapped_serialization]
        end

        # Legacy functionality translated for Rails 3 serializable_hash serialization functionality. Might get
        # a slight performance kick by using an if statement to check if :only specified, but could run in to
        # scoping issues.
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

# Add ability to map in the models. Philosophical question: add this to Object?
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

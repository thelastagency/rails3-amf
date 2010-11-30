require 'rubyamf/app/configuration'
require 'rubyamf/extensions/serialization'
require 'rubyamf/extensions/deserialization'
require 'active_record'
require 'active_resource'

require 'rails3-amf/configuration'
require 'rocketamf/pure/serializer'
require 'rocketamf/pure/deserializer'

# The only modifications to the original configuration.rb file was to do version checking on require and include
# statements which you can find by searching on fosrias in legacy_configuration.rb, which is the original
# configuration file. Any other references to fosrias are previous patch tags in the file.
module RubyAMF
  module Configuration

    # Module to be included for in-class mapping. In-class mapping registers the first time a class loads and thus
    # is automatically picked up by regular deserialization and also by using assume_types since in either case, the
    # first step is to create a new object. Thus, the first time the class loads it registers and configures both
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

        # Clears the mapping for a particular class. This is so that mapping changes in development and testing
        # are properly reset.
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
          # by bypassing mapping implementation in deserializers and serializers
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
            raise "Mapping Error. Too many options specified. :ruby and :actionscript or :as must be mapped"
          end

          # Include serialization and deserialization methods in the class when it is registered. In production mode,
          # this ensures all registered classes have their serialization properties set when the application loads.
          # In development and testing mode, this also resets serialization for the classes that have in-class mappings.
          # All other classes registered in rubyamf_config.rb or picked up by assume_types are configured by the
          # serialization methods included in RubyAMF::Serialization and the deserialization methods included in
          # RubyAMF::Deserialization, both included in ActiveRecord::Serialization.
          if ruby_class = eval(mapping[:ruby])
            ruby_class.class_eval do
              include RubyAMF::Serialization
              include RubyAMF::Deserialization
            end
          else
            raise "Attempting to register a ruby class that does not exist: #{mapping[:ruby]}."
          end
        end

        # Registers mappings for each class.
        def register_by_class_names(ruby_class_names)
          ruby_class_names.each do |ruby_class_name|
            ruby_class = eval(ruby_class_name)
            if !ruby_class
              raise "Attempting to register a ruby class that does not exist: #{ruby_class_name}."
            end
          end
        end

        # Checks if mapping is used on a model. Optimizes deserialization if mapping not used on a particular object.
        def use_mapped_serialization_for_ruby_class(ruby_class)
          return unless map = @class_mappings_by_ruby_class[ruby_class]
          map[:use_mapped_serialization]
        end

        # Legacy functionality translated for Rails 3 serializable_hash serialization functionality. This does not
        # override get_vo_mapping_for_ruby_class so that method still works.
        def get_serialization_mapping_for_ruby_class(ruby_class)
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

    # This is a bulk copy. The only change is the inclusion for Rails 3+ skipping "@persisted" variables in scaffolding.
    ParameterMappings.class_eval do
      class << self

        # remoting_params is expected to be an array of elements. Any hashes should allow indifferent access.
        def update_request_parameters(controller_class_name, controller_action_name, request_params,  rubyamf_params, remoting_params)
          if map = get_parameter_mapping(controller_class_name, controller_action_name)
            map[:params].each do |k,v|
              val = eval("remoting_params#{v}")
              if scaffolding && val.is_a?(ActiveRecord::Base)
                request_params[k.to_sym] = val.attributes.dup
                val.instance_variables.each do |assoc|
                  next if "@new_record" == assoc || "@persisted" == assoc
                  request_params[k.to_sym][assoc[1..-1]] = val.instance_variable_get(assoc)
                end
              else
                request_params[k.to_sym] = val
              end
              rubyamf_params[k.to_sym]  = request_params[k.to_sym] # assign it to rubyamf_params for consistency
            end
          else #do some default mappings for the first element in the parameters
            if remoting_params.is_a?(Array)
              if scaffolding
                if (first = remoting_params[0])
                  if first.is_a?(ActiveRecord::Base)
                    key = first.class.to_s.to_snake!.downcase.to_sym # a generated scaffold expects params in snake_case, rubyamf_params gets them for consistency in scaffolding
                    rubyamf_params[key] = first.attributes.dup
                    first.instance_variables.each do |assoc|
                      next if "@new_record" == assoc || "@persisted" == assoc
                      rubyamf_params[key][assoc[1..-1]] = first.instance_variable_get(assoc)
                    end
                    if always_add_to_params #if wanted in params, put it in
                      request_params[key] = rubyamf_params[key] #put it into rubyamf_params
                    end
                  else
                    if first.is_a?(RubyAMF::VoHelper::VoHash)
                      if (key = first.explicitType.split('::').last.to_snake!.downcase.to_sym)
                        rubyamf_params[key] = first
                        if always_add_to_params
                          request_params[key] = first
                        end
                      end
                    elsif first.is_a?(Hash) # a simple hash should become named params in params
                      rubyamf_params.merge!(first)
                      if always_add_to_params
                        request_params.merge!(first)
                      end
                    end
                  end
                  request_params[:id] = rubyamf_params[:id] = first['id'] if (first['id'] && !(first['id']==0))
                end
              end
            end
          end
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
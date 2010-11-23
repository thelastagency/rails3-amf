require 'rubyamf/legacy_configuration'
require 'rubyamf/activerecord_populator'
require 'rubyamf/registration'
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

      class << self

        alias old_register register

        #Overrides legacy register to synchronize mapping with RocketAMF
        def register(mapping)

          # Allow RocketAMF mapping symbols
          mapping[:actionscript] = mapping[:as] if mapping[:as] && !mapping[:actionscript]

          # Register the mapping in the legacy map
          old_register(mapping)

          # Register the class in RocketAMF and add associated populator
          if (mapping[:ruby] && mapping[:actionscript])

            RocketAMF::ClassMapper.define do |m|
              m.map :as => mapping[:actionscript] ||= mapping[:as], :ruby => mapping[:ruby]
            end

            #We only register the ActiveRecord populator if a rubyamf mapping requests it. Currently this affects all
            #ActiveRecord deserializations Could update the initializer so that it uses a specific model in its
            #can_handle? condition ut this could degrade performance if every active record registers its own
            #populator. Likely need to set set a custom condition here.
            if (mapping[:type] == 'active_record' && !@has_active_record_populator)
              mapping[:populator] = "ActiveRecordPopulator"
              @has_active_record_populator = true

              @has_active_resource_populator = true #TEMP until distinct populator written
            end

            if (mapping[:type] == 'active_resource' && !@has_active_resource_populator)
              mapping[:populator] = "ActiveRecordPopulator" #TEMP Currently handled in the same legacy way.
              @has_active_resource_populator = true

              @has_active_record_populator = true #TEMP until distinct populator written
            end

            # Allows registering a custom populator on the class. Typically this would be user for a custom ruby
            # class requiring advanced deserializtion/serialization
            if mapping[:populator]
              populator_class_name = mapping[:populator].to_s
              populator_class = populator_class_name.split('::').inject(Kernel) {|scope, const_name| scope.const_get(const_name)}
              if populator_class
                if mapping[:type] == 'active_record'
                  # Always put active record populators at the top
                  RocketAMF::ClassMapper.object_populators.unshift(populator_class.new)
                else
                  RocketAMF::ClassMapper.object_populators << populator_class.new
                end

              else
                raise "Attempting to add a populator that does not exist: #{populator_class_name}."
              end
            end
          end
        end

        #Registers classes as an array of class names by fully qualified package that have amf mappings registered
        #in the class. Ideally, loaded classes auto-register and thus is unnecessary.
        def register_by_class_names(ruby_class_names)

          #Load each class so that it maps itself if mappings are defined in it.
          ruby_class_names.each do |ruby_class_name|
            ruby_class = ruby_class_name.split('::').inject(Kernel) {|scope, const_name| scope.const_get(const_name)}
            if !ruby_class
              raise "Attempting to register a class that does not exist: #{ruby_class_name.to_s}."
            end
          end
        end
      end
    end
  end
end

# Add ability to map in the model.
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

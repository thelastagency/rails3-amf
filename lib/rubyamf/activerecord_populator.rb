require 'rubyamf/vo_helper'
class ActiveRecordPopulator
  
  def can_handle? obj
     obj.is_a?(ActiveRecord::Base)
   end

  def populate obj, props, dynamic_props
    obj.each_pair{|key, value| VoUtil.set_value(obj, key, value)}
    VoUtil.finalize_object(obj)
    obj
  end
end

#The complement of the populator for serialization.
module ActiveRecord
  Base.class_eval do
    include RubyAMF::VoHelper

    #Serializes the active record active record
    def to_amf options

      if options[:scope]
        scope = options.delete(:scope)
        
      end

      # Create wrapper and return
      Rails3AMF::IntermediateModel.new(self, VoUtil.get_vo_hash_for_outgoing(self))
    end
  end
end
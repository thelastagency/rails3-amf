module RocketAMF
  module Pure
    AMF3Serializer.class_eval do

      def write_array array
          write_object array, nil, {:class_name => 'flex.messaging.io.ArrayCollection', :members => [], :externalizable => true, :dynamic => false}
      end
    end
  end
end
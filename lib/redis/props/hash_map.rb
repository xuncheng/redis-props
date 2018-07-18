class Redis
  module Props
    module HashMap
      extend ActiveSupport::Concern

      included do
        include Redis::Props::Helper
      end

      module ClassMethods
        def hash_map(name, options = {})
          register_redis_props(name, :hash_map, options)

          define_method(name) do
            instance_variable_get("@#{name}") ||
              instance_variable_set("@#{name}",
                Redis::Props::Objects::Hash.new(redis_props_key(name), :pool_name => options[:redis])
              )
          end
        end
      end

      #
      # Returns the final Redis Key of a certain Redis::Props, the value will be saved in redis with
      # this key.
      #
      # Example:
      #
      # a User instance with id = 1 defines a Hash::Map named `submission_counts` -> users:1:submission_counts
      #
      # @param [String] name
      #
      # @return [String]
      #
      def redis_props_key(name)
        "#{object_key}:#{name}"
      end
    end
  end
end

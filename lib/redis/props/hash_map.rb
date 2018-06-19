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
    end
  end
end

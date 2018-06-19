class Redis
  module Props
    module Counter
      extend ::ActiveSupport::Concern

      included do
        include Redis::Props::Helper
      end

      module ClassMethods
        #
        # [counter description]
        # @param name [type] [description]
        # @param options={} [type] [description]
        # @param block [description]
        #
        # @return [type] [description]
        def counter(name, options={}, &blk)
          register_redis_props(name, :counter, options)
          redis = redis_field_redis(name)

          # Redis: GET
          define_method(name) do
            instance_variable_get("@#{name}") || begin
              value = redis.with do |conn|
                conn.hget(object_key, name)
              end || send("#{name}_default_value")
              instance_variable_set("@#{name}", value.to_i)
            end
          end

          define_method("#{name}_default_value") do
            0
          end

          # Redis: INCR
          define_method("incr_#{name}") do |by = 1|
            value = redis.with do |conn|
              conn.hincrby(object_key, name, by)
            end
            instance_variable_set("@#{name}", value.to_i)
          end

          # Redis: DECR
          define_method("decr_#{name}") do |by = 1|
            value = redis.with do |conn|
              conn.hincrby(object_key, name, -by)
            end
            instance_variable_set("@#{name}", value.to_i)
          end

          # Redis: SET
          define_method("reset_#{name}") do
            value = instance_eval(&blk)

            redis.with do |conn|
              conn.hset(object_key, name, value)
            end
            instance_variable_set("@#{name}", value)
          end

          # Redis: DEL
          define_method("remove_#{name}") do
            redis.with do |conn|
              conn.hdel(object_key, name)
            end
            remove_instance_variable("@#{name}") if instance_variable_defined?("@#{name}")
          end
        end
      end
    end
  end
end

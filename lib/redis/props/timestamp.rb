class Redis
  module Props
    module Timestamp
      extend ActiveSupport::Concern

      included do
        include Redis::Props::Helper
      end

      module ClassMethods
        #
        # [timestamp Define a timestamp]
        # @param name [type] [description]
        # @param touches={} [type] [description]
        #
        # @return [type] [description]
        def timestamp(name, options={})
          register_redis_props(name, :timestamp, options)
          redis = redis_prop_redis_pool(name)

          # Redis: GET
          define_method(name) do
            return instance_variable_get("@#{name}") if instance_variable_defined?("@#{name}")

            value = redis.with do |conn|
              raw_value = conn.hget(object_key, name)
              break raw_value if raw_value.present?

              send("#{name}_default_value").tap do |default_value|
                conn.hset(object_key, name, default_value)
              end
            end
            if value.nil? && options[:allow_nil]
              instance_variable_set("@#{name}", nil)
            else
              instance_variable_set("@#{name}", value.to_i)
            end
          end

          define_method("#{name}_default_value") do
            return nil if options[:allow_nil]
            return (Time.current.to_f * 1000).to_i if options[:digits] == 13

            Time.current.to_i
          end

          # Redis: SET
          define_method("touch_#{name}") do
            value = options[:digits] == 13 ? (Time.current.to_f * 1000).to_i : Time.current.to_i

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

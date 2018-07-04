require "redis"
require "connection_pool"
require "active_support/concern"
require "active_support/inflector"
require "redis/props/version"
require "redis/props/helper"
require "redis/props/timestamp"
require "redis/props/counter"
require "redis/props/objects/hash"
require "redis/props/hash_map"

class Redis
  module Props
    SUPPORTED_TYPES = %i(counter timestamp hash_map)

    class NilObjectId < StandardError; end
    class InvalidType < StandardError; end

    class << self
      attr_accessor :pools
      attr_accessor :redis

      def pools
        @pools ||= {}
      end

      #
      # Setup your redis connection.
      #
      # @param options={} [Hash] [Redis connection configuration]
      #   url - Redis connection url
      #   pool - Connection pool size
      #   timeout - Connection pool timeout
      #
      # @example
      #   {
      #     "default" => { "url" => "redis://localhost:6379/0", "pool" => 4, "timeout" => 2 },
      #     "norton2" => { "url" => "redis://localhost:6379/3", "pool" => 4, "timeout" => 2 }
      #   }
      #
      # @return [Void]
      #
      def setup(options = {})
        Redis::Props.pools = {}
        options.deep_symbolize_keys!

        if options.blank? || options[:default].blank?
          raise "Redis::Props couldn't initialize!"
        end

        options.each do |name, conn_params|
          pool_size = (conn_params.delete(:pool) || 1).to_i
          timeout   = (conn_params.delete(:timeout) || 2).to_i
          Redis::Props.pools[name] = ConnectionPool.new(size: pool_size, timeout: timeout) do
            Redis.new(conn_params)
          end
        end

        Redis::Props.redis = Redis::Props.pools[:default]
      end

      # 批量获取多个对象的多个 Redis::Props 字段, 仅仅支持 counter / timestamp
      #
      # @example
      #   Redis::Props.mget([a_user, another_user], [:followers_count, :profile_updated_at])
      #
      # @param [Array] names 需要检索的字段
      #
      # @return [Array] 一组对象
      #
      def mget(objects, fields)
        pools_with_name = fields.each_with_object({}) do |name, hash|
          pool = objects[0].class.redis_prop_redis_pool(name)
          hash[pool] ||= []
          hash[pool] << name
        end

        pools_with_name.each do |pool, names|
          nested_values = pool.with do |conn|
            conn.pipelined do
              objects.each { |object| conn.hmget(object.object_key, names) }
            end
          end

          objects.zip(nested_values).each do |object, values|
            object.send(:assign_values, names.zip(values).to_h)
          end
        end

        objects
      end
    end
  end
end

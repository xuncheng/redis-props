class Redis
  module Props
    module Helper
      extend ActiveSupport::Concern

      included do
        instance_variable_set(:@redis_props, {})
      end

      module ClassMethods
        attr_reader :redis_props

        #
        # 当定义一个 Redis::Props 的时候，将这个 Redis::Props 记录在 Class Variable `@redis_props` 中
        #
        #
        # @return [void]
        #
        def register_redis_props(name, field_type, options = {})
          if !Redis::Props::SUPPORTED_TYPES.include?(field_type.to_sym)
            raise Redis::Props::InvalidType.new("Redis::Props Type: #{field_type} invalid!")
          end

          @redis_props[name.to_sym] = options.symbolize_keys.merge(:type => field_type.to_sym)
        end

        #
        # 当前类是否定义了某个 Redis Prop
        #
        # @param [String/Symbol] name
        #
        # @return [Boolean]
        #
        def redis_field_defined?(name)
          redis_props.has_key?(name.to_sym)
        end

        #
        # 返回当前类定义的某个 Redis Prop 的类型
        #
        # @param [String] name
        #
        # @return [Symbol]
        #
        def redis_field_type(name)
          redis_props.dig(name.to_sym, :type)
        end

        #
        # 返回当前类定义的某个 Redis::Props 的 redis instance
        #
        # @param [String] name
        #
        # @return [ConnectionPool]
        #
        def redis_field_redis(name)
          pool_name = redis_props.dig(name.to_sym, :redis) || :default
          Redis::Props.pools[pool_name]
        end
      end

      #
      # Prefix of Redis Key of Redis::Props, consists with Class name string in plural form
      # and Instance id.
      #
      # Example:
      #
      # a User instance with id = 1 -> `users:1`
      # a HolyLight::Spammer instance with id = 5 -> `holy_light/spammers:5`
      #
      #
      # @return [String]
      #
      def redis_props_prefix
        id = self.id
        raise Redis::Props::NilObjectId if id.nil?
        klass = self.class.to_s.pluralize.underscore
        "#{klass}:#{id}"
      end

      #
      # Returns the final Redis Key of a certain Redis::Props, teh value will be saved in redis with
      # this value.
      #
      # Example:
      #
      # a User instance with id = 1 defines a counter named `likes_count` -> users:1:likes_count
      #
      #
      # @param [String] name
      #
      # @return [String]
      #
      def redis_props_key(name)
        "#{redis_props_prefix}:#{name}"
      end

      def object_key
        raise Redis::Props::NilObjectId if self.id.nil?
        "#{self.class.to_s.pluralize.underscore}:#{self.id}"
      end

      def cast_value(type, value)
        case type.to_sym
        when :counter then value.to_i
        when :timestamp then value.to_i
        end
      end

      # 批量取出当前对象的多个 Redis::Props 字段, 仅仅支持 counter / timestamp
      #
      # @param [Array] names 需要检索的字段, 例如: :field1, :field2
      #
      # @return [Model] 当前对象
      #
      def redis_props_mget(*names)
        pools_with_name = names.each_with_object({}) do |name, hash|
          pool = self.class.redis_field_redis(name)
          hash[pool] ||= []
          hash[pool] << name
        end

        pools_with_name.each do |pool, fields|
          values = pool.with do |conn|
            conn.hmget(object_key, fields)
          end

          assign_values(fields.zip(values).to_h)
        end

        self
      end

      # :nodoc
      def assign_values(new_values)
        new_values.each do |field, val|
          type = self.class.redis_field_type(field)
          ivar_name = :"@#{field}"

          case type
          when :counter
            value = cast_value(type, val || try("#{field}_default_value"))
            instance_variable_set(ivar_name, value)
          when :timestamp
            if !val.nil?
              instance_variable_set(ivar_name, cast_value(type, val))
            elsif self.class.redis_props[field][:allow_nil]
              instance_variable_set(ivar_name, nil)
            else
              value = cast_value(type, try("#{field}_default_value"))
              instance_variable_set(ivar_name, value)
              self.class.redis_field_redis(field).with do |conn|
                conn.hset(object_key, field, value)
              end
            end
          end
        end
      end
      send(:private, :assign_values)
    end
  end
end

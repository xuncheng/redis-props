require 'spec_helper'

describe Redis::Props do
  describe "#setup" do
    after(:all) do
      Redis::Props.setup(
        default: { url: "redis://localhost:6379/0" },
        tmp: { url: "redis://localhost:6379/2" }
      )
    end

    it "sets a redis connection pool" do
      Redis::Props.setup(
        default: { url: "redis://localhost:6379/0" }
      )
      expect(Redis::Props.pools[:default]).not_to be_nil
    end

    it "sets multiple redis connection pools" do
      Redis::Props.setup(
        default: { url: "redis://localhost:6379/0" },
        norton2: { url: "redis://localhost:6379/3" }
      )
      expect(Redis::Props.pools.keys).to match_array(%i[default norton2])
      expect(Redis::Props.pools[:norton2]).not_to be_nil
    end
  end

  describe ".mget" do
    class Dummy
      include Redis::Props::Counter
      include Redis::Props::Timestamp
      include Redis::Props::HashMap

      counter   :counter1
      counter   :custom_redis_counter, :redis => :tmp
      timestamp :time1
      timestamp :time2, :allow_nil => true
      hash_map  :map1

      def id
        @id ||= Random.rand(10000)
      end
    end

    let(:dummy) { Dummy.new }

    context "when the field isn't defined" do
      it "doesn't set the instance variable" do
        Redis::Props.mget([dummy], %i[undefined_field])
        expect(dummy.instance_variable_defined?(:@undefined_field)).to be(false)
      end
    end

    context "when the type isn't in the [:counter, :timestamp]" do
      it "doesn't set the instance variable" do
        Redis::Props.mget([dummy], %i[map1])
        expect(dummy.instance_variable_defined?(:@map1)).to be(false)
      end
    end

    context "when the type is in the [:counter, :timestamp]" do
      it "returns redis props correctly from redis" do
        allow(Time).to receive(:current).and_return(1234)
        dummy.incr_counter1(2)
        dummy.touch_time1

        Redis::Props.mget([dummy], %i[counter1 time1])
        expect(dummy.instance_variable_get(:@counter1)).to eq(2)
        expect(dummy.instance_variable_get(:@time1)).to eq(1234)
      end

      it "returns the default value if no value in redis" do
        allow(dummy).to receive(:counter1_default_value) { 99 }
        allow(dummy).to receive(:time1_default_value) { 1234 }

        Redis::Props.mget([dummy], %i[counter1 time1])
        expect(dummy.instance_variable_get(:@counter1)).to eq(99)
        expect(dummy.instance_variable_get(:@time1)).to eq(1234)
      end
    end

    context "when the type is :counter" do
      it "doesn't save the default value in redis if no value in redis" do
        allow(dummy).to receive(:counter1_default_value) { 99 }

        Redis::Props.mget([dummy], %i[counter1])

        value_from_redis = Redis::Props.redis.with do |conn|
          conn.hget(dummy.object_key, :counter1)
        end
        expect(value_from_redis).to be(nil)
        expect(dummy.instance_variable_get(:@counter1)).to eq(99)
      end
    end

    context "when the type is :timestamp" do
      context "when the attribute doesn't allow nil" do
        it "saves the default value in redis if no value in redis" do
          allow(dummy).to receive(:time1_default_value) { 1234 }

          dummy.redis_props_mget(:time1)

          value_from_redis = Redis::Props.redis.with do |conn|
            conn.hget(dummy.object_key, :time1)
          end.to_i
          expect(value_from_redis).to eq(1234)
        expect(dummy.instance_variable_get(:@time1)).to eq(1234)
        end
      end

      context "when the attribute allow nil" do
        it "doesn't save the default value in redis if no value in redis" do
          allow(dummy).to receive(:time2_default_value) { nil }

          dummy.redis_props_mget(:time2)

          expect(dummy.time2).to be_nil
          expect(
            Redis::Props.redis.with { |conn| conn.hexists(dummy.object_key, :time2) }
          ).to eq(false)
        end
      end
    end

    context "when the attributes in multiples redis servers" do
      it "returns the value correctly" do
        dummy.incr_counter1(2)
        dummy.incr_custom_redis_counter(99)

        Redis::Props.mget([dummy], %i[counter1 custom_redis_counter])
        expect(dummy.instance_variable_get(:@counter1)).to eq(2)
        expect(dummy.instance_variable_get(:@custom_redis_counter)).to eq(99)
      end
    end
  end
end

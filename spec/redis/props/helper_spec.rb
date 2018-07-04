require 'spec_helper'

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

module HolyLight
  class Spammer
    include Redis::Props::Counter

    def id
      @id ||= Random.rand(10000)
    end
  end
end

describe Redis::Props::Helper do
  describe ".register_redis_props" do
    it "should raise error if type is not supported" do
      expect {
        Dummy.register_redis_props("foo", "bar")
      }.to raise_error(Redis::Props::InvalidType)
    end

    it "adds the fields with valid type to `@redis_props`" do
      Dummy.register_redis_props("foo", "counter")
      expect(Dummy.redis_props[:foo][:type]).to eq(:counter)
    end

    it "adds the fields with options" do
      Dummy.register_redis_props("foo", "counter", :allow_nil => true)
      expect(Dummy.redis_props[:foo][:type]).to eq(:counter)
      expect(Dummy.redis_props[:foo][:allow_nil]).to eq(true)
    end
  end

  describe ".redis_prop_defined?" do
    it "should return true for a defined value" do
      expect(Dummy.redis_prop_defined?(:counter1)).to eq(true)
    end

    it "should return false for a undefined value" do
      expect(Dummy.redis_prop_defined?(:time3)).to eq(false)
    end
  end

  describe ".redis_prop_type" do
    it "returns the type for a defined prop" do
      Dummy.register_redis_props("foo", "counter")
      expect(Dummy.redis_prop_type("foo")).to eq(:counter)
    end
  end

  describe "#object_key" do
    let(:dummy) { Dummy.new }
    let(:spammer) { HolyLight::Spammer.new }

    it "raises error if the object's id is nil" do
      allow(dummy).to receive(:id) { nil }
      expect { dummy.object_key }.to raise_error(Redis::Props::NilObjectId)
    end

    it "returns correctly for valid objects" do
      expect(dummy.object_key).to eq("dummies:#{dummy.id}")
      expect(spammer.object_key).to eq("holy_light/spammers:#{spammer.id}")
    end

    it "should return correctly for `HolyLight::Spammer`" do
      spammer = HolyLight::Spammer.new
      expect(spammer.object_key).to eq("holy_light/spammers:#{spammer.id}")
    end
  end

  describe "#redis_props_mget" do
    let(:dummy) { Dummy.new }

    context "when the field isn't defined" do
      it "doesn't set the instance variable" do
        dummy.redis_props_mget(:undefined_field)
        expect(dummy.instance_variable_defined?(:@undefined_field)).to be(false)
      end
    end

    context "when the type isn't in the [:counter, :timestamp]" do
      it "doesn't set the instance variable" do
        dummy.redis_props_mget(:map1)
        expect(dummy.instance_variable_defined?(:@map1)).to be(false)
      end
    end

    context "when the type is in the [:counter, :timestamp]" do
      it "returns redis props correctly from redis" do
        allow(Time).to receive(:current).and_return(1234)
        dummy.incr_counter1(2)
        dummy.touch_time1

        dummy.redis_props_mget(:counter1, :time1)
        expect(dummy.instance_variable_get(:@counter1)).to eq(2)
        expect(dummy.instance_variable_get(:@time1)).to eq(1234)
      end

      it "returns the default value if no value in redis" do
        allow(dummy).to receive(:counter1_default_value) { 99 }
        allow(dummy).to receive(:time1_default_value) { 1234 }

        dummy.redis_props_mget(:counter1, :time1)
        expect(dummy.instance_variable_get(:@counter1)).to eq(99)
        expect(dummy.instance_variable_get(:@time1)).to eq(1234)
      end
    end

    context "when the type is :counter" do
      it "doesn't save the default value in redis if no value in redis" do
        allow(dummy).to receive(:counter1_default_value) { 99 }

        dummy.redis_props_mget(:counter1)

        value_from_redis = Redis::Props.redis.with do |conn|
          conn.get(dummy.redis_props_key(:counter1))
        end
        expect(value_from_redis).to be(nil)
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
          expect(dummy.time1).to eq(1234)
        end
      end

      context "when the attribute allow nil" do
        it "doesn't save the default value in redis if no value in redis" do
          allow(dummy).to receive(:time2_default_value) { nil }

          dummy.redis_props_mget(:time2)

          expect(dummy.time2).to be_nil
          expect(
            Redis::Props.redis.with { |conn| conn.exists(dummy.redis_props_key(:time2)) }
          ).to eq(false)
        end
      end
    end

    context "when the attributes in multiples redis servers" do
      it "returns the value correctly" do
        dummy.incr_counter1(2)
        dummy.incr_custom_redis_counter(99)

        dummy.redis_props_mget(:counter1, :custom_redis_counter)
        expect(dummy.instance_variable_get(:@counter1)).to eq(2)
        expect(dummy.instance_variable_get(:@custom_redis_counter)).to eq(99)
      end
    end
  end
end

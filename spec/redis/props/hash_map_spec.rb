require 'spec_helper'

class HashMapObject
  include Redis::Props::HashMap

  hash_map :profile

  def id
    @id ||= 99
  end
end

describe Redis::Props::HashMap do
  describe "#redis_props_key" do
    it "generates the correct field key" do
      object = HashMapObject.new
      expect(object.redis_props_key(:profile)).to eq("hash_map_objects:99:profile")
    end
  end

  describe "#hash_map" do
    it "sets a instance variable" do
      object = HashMapObject.new
      expect(object.profile).to be_a(Redis::Props::Objects::Hash)
    end
  end
end

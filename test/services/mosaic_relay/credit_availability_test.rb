# frozen_string_literal: true

require "test_helper"

class MosaicRelayCreditAvailabilityTest < ActiveSupport::TestCase
  class FakeRedis
    def initialize
      @values = {}
    end

    def get(key) = @values[key]

    def set(key, value, nx: false, ex: nil)
      return nil if nx && @values.key?(key)

      @values[key] = value
      "OK"
    end

    def del(key)
      @values.delete(key)
      1
    end

    def eval(_script, keys:, argv:)
      del(keys.first) if get(keys.first) == argv.first
    end
  end

  class FakeBroadcaster
    attr_reader :events

    def initialize
      @events = []
    end

    def broadcast(stream, payload)
      events << [ stream, payload ]
    end
  end

  setup do
    @redis = FakeRedis.new
    @broadcaster = FakeBroadcaster.new
    MosaicRelay.configure do |config|
      config.chat_tenant_key = "mosaic-site"
      config.redis = @redis
      config.broadcaster = @broadcaster
    end
    @availability = MosaicRelay::CreditAvailability.new
  end

  teardown do
    MosaicRelay.reset_configuration!
  end

  test "is available until a future reset time is recorded" do
    assert @availability.available?

    reset_at = 2.hours.from_now.iso8601
    assert @availability.mark_unavailable!(resets_at: reset_at)
    assert_not @availability.available?
    assert_equal [
      [ MosaicRelay::CreditAvailability.stream_name, { type: "chat_unavailable" } ]
    ], @broadcaster.events
  end

  test "keeps the latest reset time and broadcasts only when state changes" do
    earlier = 1.hour.from_now.iso8601
    later = 2.hours.from_now.iso8601

    assert @availability.mark_unavailable!(resets_at: earlier)
    assert @availability.mark_unavailable!(resets_at: later)
    assert_not @availability.mark_unavailable!(resets_at: earlier)

    assert_equal later, @redis.get("relay_chat_unavailable_until:mosaic-site")
    assert_equal 2, @broadcaster.events.length
  end

  test "clears the unavailable circuit" do
    @availability.mark_unavailable!(resets_at: 2.hours.from_now.iso8601)

    assert @availability.clear_unavailability!
    assert @availability.available?
  end
end

# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"

class MosaicRelayCursorCodecTest < ActiveSupport::TestCase
  test "round trips a versioned cursor payload" do
    payload = { "mode" => "snapshot", "phase" => "pages", "last_id" => 42 }

    encoded = MosaicRelay::CursorCodec.encode(payload)

    assert_not_includes encoded, "="
    assert_equal payload.merge("v" => MosaicRelay::CursorCodec::VERSION), MosaicRelay::CursorCodec.decode(encoded)
  end

  test "normalizes symbol payload keys without mutating the input" do
    payload = { mode: "events", after: 10 }

    decoded = MosaicRelay::CursorCodec.decode(MosaicRelay::CursorCodec.encode(payload))

    assert_equal({ "mode" => "events", "after" => 10, "v" => 1 }, decoded)
    assert_equal({ mode: "events", after: 10 }, payload)
  end

  test "returns nil for a blank cursor" do
    assert_nil MosaicRelay::CursorCodec.decode(nil)
    assert_nil MosaicRelay::CursorCodec.decode("")
    assert_nil MosaicRelay::CursorCodec.decode("   ")
  end

  test "rejects malformed cursors" do
    assert_raises MosaicRelay::CursorCodec::InvalidCursor do
      MosaicRelay::CursorCodec.decode("not-a-cursor")
    end

    invalid_json = Base64.urlsafe_encode64("not json", padding: false)
    assert_raises MosaicRelay::CursorCodec::InvalidCursor do
      MosaicRelay::CursorCodec.decode(invalid_json)
    end
  end

  test "rejects cursors with a missing or unsupported version" do
    [ {}, { "v" => 999 } ].each do |payload|
      cursor = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)

      assert_raises MosaicRelay::CursorCodec::InvalidCursor do
        MosaicRelay::CursorCodec.decode(cursor)
      end
    end
  end

  test "rejects non hash-like encode input" do
    assert_raises ArgumentError do
      MosaicRelay::CursorCodec.encode("snapshot")
    end
  end
end

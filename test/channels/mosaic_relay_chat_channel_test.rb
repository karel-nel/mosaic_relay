# frozen_string_literal: true

require "test_helper"

class MosaicRelayChatChannelTest < ActionCable::Channel::TestCase
  tests MosaicRelay::RelayChatChannel

  test "streams credit availability events for the configured tenant" do
    MosaicRelay.configure { |config| config.chat_tenant_key = "mosaic-site" }

    subscribe

    assert_has_stream MosaicRelay::CreditAvailability.stream_name
  ensure
    MosaicRelay.reset_configuration!
  end
end

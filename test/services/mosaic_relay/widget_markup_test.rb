# frozen_string_literal: true

require "test_helper"

class MosaicRelayWidgetMarkupTest < ActiveSupport::TestCase
  test "removes script tags from the trusted mount markup" do
    markup = '<script src="https://relay.example/widget.js"></script><niimble-relay-chat widget-key="public"></niimble-relay-chat>'

    assert_equal '<niimble-relay-chat widget-key="public"></niimble-relay-chat>',
                 MosaicRelay::WidgetMarkup.mount_markup(markup)
  end

  test "uses an explicit public script source" do
    markup = '<script src="https://relay.example/widget.js"></script><niimble-relay-chat></niimble-relay-chat>'

    assert_equal "https://relay.example/widget.js", MosaicRelay::WidgetMarkup.script_url(markup)
  end

  test "derives the public script source from relay-url markup" do
    markup = '<niimble-relay-chat relay-url="https://relay.example/"></niimble-relay-chat>'

    assert_equal "https://relay.example/niimble-relay-widget.js", MosaicRelay::WidgetMarkup.script_url(markup)
  end

  test "rejects non-public script sources" do
    markup = '<script src="/widget.js"></script><niimble-relay-chat relay-url="javascript:alert(1)"></niimble-relay-chat>'

    assert_nil MosaicRelay::WidgetMarkup.script_url(markup)
  end
end

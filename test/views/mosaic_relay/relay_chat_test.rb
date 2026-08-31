# frozen_string_literal: true

require "test_helper"

class MosaicRelayRelayChatViewTest < ActionView::TestCase
  setup do
    MosaicRelay::ApplicationController.view_paths = [ MosaicRelay::Engine.root.join("app/views") ]
    MosaicRelay::RelaySetting.delete_all
    MosaicRelay::RelaySetting.current.update!(widget_markup: '<niimble-relay-chat relay-url="https://relay.example" widget-key="nrw_public-key"></niimble-relay-chat>')
  end

  teardown do
    MosaicRelay.reset_configuration!
    MosaicRelay::RelaySetting.delete_all
  end

  test "renders Relay's mount markup without Mosaic chat UI" do
    rendered = render partial: "pods/shared/relay_chat"

    assert_includes rendered, "<relay-llm-widget>"
    assert_includes rendered, 'widget-key="nrw_public-key"'
    assert_includes rendered, 'src="https://relay.example/niimble-relay-widget.js"'
    refute_includes rendered, 'data-controller="llm-chat"'
  end

  test "loads the Relay script once per view context" do
    first = render partial: "pods/shared/relay_chat"
    second = render partial: "pods/shared/relay_chat"

    assert_includes first, "niimble-relay-widget.js"
    refute_includes second, "niimble-relay-widget.js"
  end
end

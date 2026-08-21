# frozen_string_literal: true

require "test_helper"

class MosaicRelayLlmChatWindowViewTest < ActionView::TestCase
  setup do
    MosaicRelay::ApplicationController.view_paths = [ MosaicRelay::Engine.root.join("app/views") ]
  end

  test "renders the LLM chat Pod with its controller and endpoint values" do
    rendered = render partial: "pods/shared/llm_chat_window"

    assert_includes rendered, 'data-controller="llm-chat"'
    assert_includes rendered, 'data-llm-chat-url-value="/mosaic_relay/api/relay/chat"'
    assert_includes rendered, 'data-llm-chat-availability-url-value="/mosaic_relay/api/relay/chat/availability"'
    assert_includes rendered, 'data-llm-chat-allow-insecure-assets-value="false"'
  end

  test "renders every Stimulus target required by the controller" do
    rendered = render partial: "pods/shared/llm_chat_window"

    %w[
      initial conversation form input messages typing sendButton sources
      sourceCount emptySources resetButton
    ].each do |target|
      assert_includes rendered, %(data-llm-chat-target="#{target}")
    end
  end

  test "renders the fixed Niimble branding and extracted footer" do
    rendered = render partial: "pods/shared/llm_chat_window"

    assert_includes rendered, "Niimble Relay"
    assert_includes rendered, "Niimble Relay developed by"
    assert_match %r{src="/assets/niimble-logo-light-tp(?:-[^"]+)?\.png"}, rendered
  end
end

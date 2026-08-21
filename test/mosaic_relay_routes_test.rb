# frozen_string_literal: true

require "test_helper"

class MosaicRelayRoutesTest < ActiveSupport::TestCase
  test "generates mounted chat endpoint paths for the Pod" do
    routes = MosaicRelay::Engine.routes.url_helpers

    assert_equal "/mosaic_relay/api/relay/chat", routes.api_relay_chat_path
    assert_equal "/mosaic_relay/api/relay/chat/availability", routes.api_relay_chat_availability_path
    assert_equal "/mosaic_relay/api/relay/documents", routes.api_relay_documents_path
  end

  test "the Pod uses the engine route helpers" do
    view_path = MosaicRelay::Engine.root.join("app/views/pods/shared/_llm_chat_window.html.erb")
    view = File.read(view_path)

    assert_includes view, "MosaicRelay::Engine.routes.url_helpers.api_relay_chat_path"
    assert_includes view, "MosaicRelay::Engine.routes.url_helpers.api_relay_chat_availability_path"
  end
end

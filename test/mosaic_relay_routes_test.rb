# frozen_string_literal: true

require "test_helper"

class MosaicRelayRoutesTest < ActiveSupport::TestCase
  test "keeps the mounted document endpoint" do
    routes = MosaicRelay::Engine.routes.url_helpers

    assert_equal "/mosaic_relay/api/relay/documents", routes.api_relay_documents_path
    refute routes.respond_to?(:api_relay_chat_path)
    refute routes.respond_to?(:api_relay_chat_availability_path)
  end

  test "registers the host admin Relay Settings routes" do
    routes = Rails.application.routes.url_helpers

    assert_equal "/admin/relay_settings", routes.mosaic_relay_settings_path
    assert_equal "/admin/relay_settings/generate_bearer_token", routes.mosaic_relay_generate_bearer_token_path
  end
end

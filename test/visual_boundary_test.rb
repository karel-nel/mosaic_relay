# frozen_string_literal: true

require "test_helper"

class MosaicRelayVisualBoundaryTest < ActiveSupport::TestCase
  CHAT_IMPLEMENTATION_PATHS = %w[
    app/channels/mosaic_relay/relay_chat_channel.rb
    app/controllers/mosaic_relay/api/relay/chats_controller.rb
    app/javascript/controllers/llm_chat_controller.js
    app/services/mosaic_relay/chat_client.rb
    app/services/mosaic_relay/citation_image_resolver.rb
    app/services/mosaic_relay/credit_availability.rb
    app/views/pods/shared/_llm_chat_window.html.erb
    app/views/pods/shared/_llm_chat_footer.html.erb
    app/assets/stylesheets/mosaic_relay/llm_chat.css
    app/assets/images/niimble-logo-light-tp.png
  ].freeze

  test "ships no legacy chat browser implementation or proxy" do
    CHAT_IMPLEMENTATION_PATHS.each do |path|
      refute File.exist?(MosaicRelay::Engine.root.join(path)), "Expected #{path} not to be shipped"
    end
  end

  test "does not expose legacy chat or Redis configuration" do
    configuration = MosaicRelay.configuration

    %i[
      chat_base_url chat_token chat_tenant_key chat_open_timeout_seconds
      chat_read_timeout_seconds redis broadcaster
    ].each do |attribute|
      refute_respond_to configuration, attribute
    end

    refute_respond_to MosaicRelay, :configure_from_env!
  end

  test "ships only the canonical Relay widget Pod definition" do
    assert_equal "Relay Chat", MosaicRelay::PodDefinition.relay_chat.fetch("name")
    refute MosaicRelay::PodDefinition.definitions.fetch("pod_definitions").key?("llm_chat_window")
  end
end

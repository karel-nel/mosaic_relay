# frozen_string_literal: true

require "test_helper"

class MosaicRelayPodDefinitionTest < ActiveSupport::TestCase
  test "defines the canonical Relay widget Pod" do
    definition = MosaicRelay::PodDefinition.relay_chat

    assert_equal "Relay Chat", definition.fetch("name")
    assert_equal "Mounts the Relay-owned chat widget.", definition.fetch("description")
    assert_equal "content", definition.fetch("category")
    assert_equal "chat", definition.fetch("icon")
    assert_equal({}, definition.fetch("schema"))
  end

  test "does not retain the legacy chat window definition" do
    definitions = MosaicRelay::PodDefinition.definitions.fetch("pod_definitions")

    assert_equal [ "relay_chat" ], definitions.keys
    refute definitions.key?("llm_chat_window")
  end
end

# frozen_string_literal: true

require "test_helper"

class MosaicRelayPodDefinitionTest < ActiveSupport::TestCase
  test "loads the extracted Mosaic pod definition" do
    assert_path_exists MosaicRelay::PodDefinition.path

    definitions = MosaicRelay::PodDefinition.definitions
    assert_kind_of Hash, definitions
    assert_equal [ "llm_chat_window" ], definitions.fetch("pod_definitions").keys
  end

  test "defines the LLM chat pod metadata" do
    definition = MosaicRelay::PodDefinition.llm_chat_window

    assert_equal "LLM Chat Window", definition["name"]
    assert_equal "content", definition["category"]
    assert_equal "chat", definition["icon"]
    assert_equal true, definition["usable_in_sections"]
    assert_equal [ "content", "tabs" ], definition["recommended_for"]
  end

  test "defines the required title field" do
    title = MosaicRelay::PodDefinition.llm_chat_window.fetch("schema").fetch("Title")

    assert_equal "text", title["type"]
    assert_equal "Title", title["label"]
    assert_equal 10, title["position"]
    assert_equal true, title["required"]
    assert_equal "content", title["inspector_group"]
  end
end

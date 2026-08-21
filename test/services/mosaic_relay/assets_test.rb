# frozen_string_literal: true

require "test_helper"

class MosaicRelayAssetsTest < ActiveSupport::TestCase
  test "ships the LLM chat scrollbar stylesheet and Niimble logo" do
    engine_root = MosaicRelay::Engine.root
    stylesheet = engine_root.join("app/assets/stylesheets/mosaic_relay/llm_chat.css")
    logo = engine_root.join("app/assets/images/niimble-logo-light-tp.png")

    assert_path_exists stylesheet
    assert_path_exists logo
    assert_includes File.read(stylesheet), ".llm-chat-scrollbar"
  end
end

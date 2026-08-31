# frozen_string_literal: true

require "test_helper"

class MosaicRelayMigrationContractTest < ActiveSupport::TestCase
  test "keeps the feed endpoint stable" do
    assert_equal "/mosaic_relay/api/relay/documents",
                 MosaicRelay::MigrationContract::DOCUMENTS_ENDPOINT_PATH
  end

  test "uses relay_chat as the canonical Pod type" do
    contract = MosaicRelay::MigrationContract

    assert contract.canonical_pod_type?("relay_chat")
    assert contract.legacy_pod_type?("llm_chat_window")
    assert_equal "relay_chat", contract.pod_type("llm_chat_window")
    assert_equal "relay_chat", contract.pod_type("relay_chat")
  end

  test "preserves stable source external IDs" do
    contract = MosaicRelay::MigrationContract

    assert_equal "pages:42", contract.external_id("pages", 42)
    assert_equal "blogs:7", contract.external_id("blogs", 7)
  end

  test "rejects unknown sources and missing record IDs" do
    contract = MosaicRelay::MigrationContract

    assert_raises(ArgumentError) { contract.external_id("events", 1) }
    assert_raises(ArgumentError) { contract.external_id("pages", nil) }
  end
end

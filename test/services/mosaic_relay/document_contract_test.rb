# frozen_string_literal: true

require "test_helper"

class MosaicRelayDocumentContractTest < ActiveSupport::TestCase
  VALID_DOCUMENT = {
    "external_id" => "pages:race-day",
    "title" => "Race day information",
    "url" => "https://mosaic.example/race-day",
    "content" => "Registration opens at 08:00.",
    "content_type" => "page",
    "language" => "en",
    "updated_at" => "2026-08-12T10:15:00Z",
    "content_hash" => "a7d4f5087024f93c0b6efab3fd3f33f9d46544a3b84fa7dd9c380153d9a1f771",
    "deleted" => false,
    "content_blocks" => [ { "kind" => "paragraph", "text" => "Registration opens at 08:00." } ],
    "metadata" => {}
  }.freeze

  test "accepts a canonical active document" do
    assert_equal VALID_DOCUMENT, MosaicRelay::DocumentContract.validate!(VALID_DOCUMENT)
  end

  test "accepts the minimal deletion record" do
    deletion = { external_id: "pages:obsolete", deleted: true }

    assert_equal({ "external_id" => "pages:obsolete", "deleted" => true },
                 MosaicRelay::DocumentContract.validate!(deletion))
  end

  test "defaults optional active document fields" do
    document = VALID_DOCUMENT.except("deleted", "content_blocks", "metadata")

    assert_equal false, MosaicRelay::DocumentContract.validate!(document)["deleted"]
    assert_equal [], MosaicRelay::DocumentContract.validate!(document)["content_blocks"]
    assert_equal({}, MosaicRelay::DocumentContract.validate!(document)["metadata"])
  end

  test "validates every document in a feed envelope" do
    envelope = { documents: [ VALID_DOCUMENT ], cursor: "opaque-cursor" }

    assert_equal "opaque-cursor", MosaicRelay::DocumentContract.validate_envelope!(envelope)["cursor"]
  end

  test "rejects active documents with missing fields" do
    error = assert_raises MosaicRelay::DocumentContract::InvalidDocument do
      MosaicRelay::DocumentContract.validate!(VALID_DOCUMENT.except("content_hash"))
    end

    assert_includes error.message, "content_hash"
  end

  test "rejects malformed content hashes" do
    error = assert_raises MosaicRelay::DocumentContract::InvalidDocument do
      MosaicRelay::DocumentContract.validate!(VALID_DOCUMENT.merge("content_hash" => "not-a-sha"))
    end

    assert_includes error.message, "content_hash"
  end
end

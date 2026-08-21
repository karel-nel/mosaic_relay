# frozen_string_literal: true

require "test_helper"

class MosaicRelayDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    MosaicRelay.configure { |configuration| configuration.source_token = "source-secret" }
    @headers = { "Authorization" => "Bearer source-secret" }
  end

  teardown do
    MosaicRelay.reset_configuration!
  end

  test "rejects requests without a source token" do
    get "/mosaic_relay/api/relay/documents"

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.fetch("error")
  end

  test "rejects requests with an invalid source token" do
    get "/mosaic_relay/api/relay/documents", headers: { "Authorization" => "Bearer wrong-secret" }

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.fetch("error")
  end

  test "requires the bearer authentication scheme" do
    get "/mosaic_relay/api/relay/documents", headers: { "Authorization" => "Basic source-secret" }

    assert_response :unauthorized
  end

  test "passes the cursor to the document feed and renders its response" do
    calls = []
    feed = Struct.new(:call).new({ "documents" => [], "cursor" => "next-cursor" })

    stub_class_method(MosaicRelay::DocumentFeed, :new, ->(cursor:) { calls << cursor; feed }) do
      get "/mosaic_relay/api/relay/documents", params: { cursor: "current-cursor" }, headers: @headers
    end

    assert_response :success
    assert_equal [ "current-cursor" ], calls
    assert_equal({ "documents" => [], "cursor" => "next-cursor" }, response.parsed_body)
  end

  test "returns a JSON validation error for an invalid cursor" do
    stub_class_method(MosaicRelay::DocumentFeed, :new, ->(**) { raise MosaicRelay::CursorCodec::InvalidCursor }) do
      get "/mosaic_relay/api/relay/documents", params: { cursor: "invalid" }, headers: @headers
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", response.parsed_body.fetch("error")
  end
end

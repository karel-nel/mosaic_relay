# frozen_string_literal: true

require "test_helper"
require "net/http"

class MosaicRelayChatClientTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:code, :body) do
    def is_a?(klass)
      return true if klass == Net::HTTPSuccess && code.to_i.between?(200, 299)

      super
    end
  end

  setup do
    MosaicRelay.configure_from_env!({
      "RELAY_PUBLIC_BASE_URL" => "https://mosaic.example",
      "RELAY_CHAT_BASE_URL" => "https://relay.example/",
      "RELAY_CHAT_TOKEN" => "secret-token"
    })
  end

  teardown do
    MosaicRelay.reset_configuration!
  end

  test "posts the conversation payload to Relay" do
    test_case = self
    captured_request = nil
    response = FakeResponse.new(code: "200", body: { "answer" => "Hello" }.to_json)
    http = Object.new
    http.define_singleton_method(:request) do |request|
      captured_request = request
      response
    end

    stub_class_method(Net::HTTP, :start, lambda { |host, port, use_ssl:, open_timeout:, read_timeout:, &block|
      test_case.assert_equal "relay.example", host
      test_case.assert_equal 443, port
      test_case.assert use_ssl
      test_case.assert_equal 5, open_timeout
      test_case.assert_equal 45, read_timeout
      block.call(http)
    }) do
      result = MosaicRelay::ChatClient.call(
        conversation_id: "conversation-123",
        message: "How do I qualify?",
        visitor_id: "visitor-123",
        context: { "interface" => "web" }
      )

      assert_equal 200, result.status
      assert_equal({ "answer" => "Hello" }, result.payload)
    end

    assert_equal URI("https://relay.example/api/v1/chat/messages"), captured_request.uri
    assert_equal "Bearer secret-token", captured_request["Authorization"]
    assert_equal "application/json", captured_request["Content-Type"]
    assert_equal({
      "conversation_id" => "conversation-123",
      "message" => "How do I qualify?",
      "visitor_id" => "visitor-123",
      "context" => { "interface" => "web" }
    }, JSON.parse(captured_request.body))
  end

  test "raises a configuration error when the Relay endpoint is missing" do
    MosaicRelay.configure { |config| config.chat_base_url = "" }

    error = assert_raises MosaicRelay::ChatClient::ConfigurationError do
      MosaicRelay::ChatClient.call(conversation_id: nil, message: "Hello", visitor_id: nil, context: {})
    end

    assert_equal "Relay chat has not been configured yet.", error.message
  end

  test "converts network failures into an upstream error" do
    stub_class_method(Net::HTTP, :start, ->(*) { raise Net::OpenTimeout }) do
      error = assert_raises MosaicRelay::ChatClient::UpstreamError do
        MosaicRelay::ChatClient.call(conversation_id: nil, message: "Hello", visitor_id: nil, context: {})
      end

      assert_equal "The Relay chat service is unavailable. Please try again shortly.", error.message
    end
  end

  test "converts malformed upstream JSON into an upstream error" do
    response = FakeResponse.new(code: "200", body: "not-json")
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }

    stub_class_method(Net::HTTP, :start, ->(*, **, &block) { block.call(http) }) do
      error = assert_raises MosaicRelay::ChatClient::UpstreamError do
        MosaicRelay::ChatClient.call(conversation_id: nil, message: "Hello", visitor_id: nil, context: {})
      end

      assert_equal "The Relay chat service returned an unexpected response.", error.message
    end
  end
end

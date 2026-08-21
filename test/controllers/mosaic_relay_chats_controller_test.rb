# frozen_string_literal: true

require "test_helper"

class MosaicRelayChatsControllerTest < ActionDispatch::IntegrationTest
  CHAT_PATH = "/mosaic_relay/api/relay/chat"
  AVAILABILITY_PATH = "/mosaic_relay/api/relay/chat/availability"

  test "proxies a browser chat request to Relay" do
    test_case = self
    payload = {
      "conversation_id" => "conversation-123",
      "message_id" => "message-123",
      "answer" => "You need to complete ten Comrades Marathons.",
      "citations" => [],
      "fallback" => false
    }

    stub_class_method(MosaicRelay::CreditAvailability, :available?, ->(*) { true }) do
      stub_class_method(MosaicRelay::ChatClient, :call, lambda { |**arguments|
        test_case.assert_equal "How do I earn a Green Number?", arguments.fetch(:message)
        test_case.assert_equal "visitor-123", arguments.fetch(:visitor_id)
        test_case.assert_equal "web", arguments.dig(:context, "interface")
        MosaicRelay::ChatClient::Response.new(status: 200, payload: payload)
      }) do
        post CHAT_PATH, params: {
          message: "How do I earn a Green Number?",
          visitor_id: "visitor-123",
          context: { current_url: "https://mosaic.example", locale: "en-ZA", interface: "web", interface_type: "web" }
        }, as: :json
      end
    end

    assert_response :success
    assert_equal payload, response.parsed_body
  end

  test "requires a message" do
    stub_class_method(MosaicRelay::CreditAvailability, :available?, ->(*) { true }) do
      post CHAT_PATH, params: {}, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_request", response.parsed_body.fetch("error")
  end

  test "returns unavailable when the shared circuit is open" do
    test_case = self
    stub_class_method(MosaicRelay::CreditAvailability, :available?, ->(*) { false }) do
      stub_class_method(MosaicRelay::ChatClient, :call, ->(**) { test_case.flunk "Relay must not be called" }) do
        post CHAT_PATH, params: { message: "Hello" }, as: :json
      end
    end

    assert_response :success
    assert_equal({ "chat_unavailable" => true }, response.parsed_body)
  end

  test "availability endpoint returns the generic availability flag" do
    stub_class_method(MosaicRelay::CreditAvailability, :available?, ->(*) { false }) do
      get AVAILABILITY_PATH
    end

    assert_response :success
    assert_equal({ "available" => false }, response.parsed_body)
  end
end

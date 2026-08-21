# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module MosaicRelay
  class ChatClient
    class ConfigurationError < StandardError; end
    class UpstreamError < StandardError; end

    Response = Data.define(:status, :payload)

    def self.call(**) = new(**).call

    def initialize(conversation_id:, message:, visitor_id:, context:)
      @conversation_id = conversation_id.presence
      @message = message
      @visitor_id = visitor_id.presence
      @context = context
    end

    def call
      uri = chat_messages_uri
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: configuration.chat_open_timeout_seconds,
        read_timeout: configuration.chat_read_timeout_seconds
      ) { |http| http.request(request_for(uri)) }

      payload = parse_payload(response)
      payload = CitationImageResolver.enrich(payload) if response.is_a?(Net::HTTPSuccess)
      Response.new(status: response.code.to_i, payload:)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, URI::InvalidURIError
      raise UpstreamError, "The Relay chat service is unavailable. Please try again shortly."
    end

    private

    attr_reader :conversation_id, :message, :visitor_id, :context

    def configuration
      MosaicRelay.configuration
    end

    def chat_messages_uri
      base_url = configuration.chat_base_url
      token = configuration.chat_token
      raise ConfigurationError, "Relay chat has not been configured yet." if base_url.blank? || token.blank?

      URI.join("#{base_url}/", "api/v1/chat/messages")
    end

    def request_for(uri)
      Net::HTTP::Post.new(uri).tap do |request|
        request["Authorization"] = "Bearer #{configuration.chat_token}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = {
          conversation_id:,
          message:,
          visitor_id:,
          context:
        }.compact.to_json
      end
    end

    def parse_payload(response)
      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError
      raise UpstreamError, "The Relay chat service returned an unexpected response."
    end
  end
end

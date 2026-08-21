# frozen_string_literal: true

require "base64"
require "json"

module MosaicRelay
  class CursorCodec
    class InvalidCursor < StandardError; end

    VERSION = 1

    class << self
      def encode(payload)
        unless payload.respond_to?(:to_h)
          raise ArgumentError, "cursor payload must be a Hash-like object"
        end

        normalized = payload.to_h.transform_keys(&:to_s)
        Base64.urlsafe_encode64(JSON.generate(normalized.merge("v" => VERSION)), padding: false)
      end

      def decode(value)
        return if value.blank?

        decoded = JSON.parse(Base64.urlsafe_decode64(pad(value.to_s)))
        raise InvalidCursor unless decoded.is_a?(Hash) && decoded["v"] == VERSION

        decoded
      rescue ArgumentError, JSON::ParserError, TypeError
        raise InvalidCursor
      end

      private

      def pad(value)
        value + ("=" * ((4 - value.length % 4) % 4))
      end
    end
  end
end

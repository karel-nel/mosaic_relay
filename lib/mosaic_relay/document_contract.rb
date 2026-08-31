# frozen_string_literal: true

require "uri"

module MosaicRelay
  # Validates the canonical document shape exchanged by Mosaic and Relay.
  #
  # Active documents contain the full searchable document payload. Deletion
  # records intentionally use the smaller { external_id, deleted } shape.
  class DocumentContract
    REQUIRED_ACTIVE_FIELDS = %w[
      external_id
      title
      url
      content
      content_type
      language
      updated_at
      content_hash
    ].freeze

    class InvalidDocument < ArgumentError; end

    class << self
      def validate!(document)
        payload = stringify_keys(document)
        raise InvalidDocument, "document must be a Hash" unless payload.is_a?(Hash)
        raise InvalidDocument, "external_id is required" if payload["external_id"].to_s.empty?

        return payload if payload["deleted"] == true

        payload["deleted"] = false unless payload.key?("deleted")
        payload["content_blocks"] = [] unless payload.key?("content_blocks")
        payload["metadata"] = {} unless payload.key?("metadata")

        missing = REQUIRED_ACTIVE_FIELDS.reject { |field| payload.key?(field) }
        raise InvalidDocument, "missing required fields: #{missing.join(', ')}" if missing.any?

        validate_active_document!(payload)
        payload
      end

      def validate_envelope!(envelope)
        payload = stringify_keys(envelope)
        raise InvalidDocument, "feed response must be a Hash" unless payload.is_a?(Hash)
        raise InvalidDocument, "documents must be an Array" unless payload["documents"].is_a?(Array)

        payload["documents"].each { |document| validate!(document) }
        payload
      end

      private

      def validate_active_document!(payload)
        raise InvalidDocument, "deleted must be false for active documents" unless payload["deleted"] == false
        raise InvalidDocument, "content_blocks must be an Array" unless payload["content_blocks"].is_a?(Array)
        raise InvalidDocument, "metadata must be a Hash" unless payload["metadata"].is_a?(Hash)
        validate_absolute_url!(payload["url"])

        unless payload["content_hash"].to_s.match?(/\A[0-9a-f]{64}\z/)
          raise InvalidDocument, "content_hash must be a lowercase SHA-256 hex digest"
        end
      end

      def validate_absolute_url!(value)
        uri = URI.parse(value.to_s)
        return if uri.is_a?(URI::HTTP) && uri.host.present?

        raise InvalidDocument, "url must be an absolute HTTP(S) URL"
      rescue URI::InvalidURIError
        raise InvalidDocument, "url must be an absolute HTTP(S) URL"
      end

      def stringify_keys(value)
        return value unless value.is_a?(Hash)

        value.to_h.transform_keys(&:to_s)
      end
    end
  end
end

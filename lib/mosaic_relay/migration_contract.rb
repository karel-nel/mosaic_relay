# frozen_string_literal: true

module MosaicRelay
  # The stable, cross-version boundary between MosaicRelay and Relay.
  #
  # Keep these values independent from implementation details. A migration may
  # replace the chat UI, settings storage, or feed internals, but it must not
  # silently change the identifiers Relay uses to reconcile documents.
  module MigrationContract
    VERSION = 1
    DOCUMENTS_ENDPOINT_PATH = "/mosaic_relay/api/relay/documents"

    CANONICAL_POD_TYPE = "relay_chat"
    LEGACY_POD_TYPES = %w[llm_chat_window].freeze

    SOURCE_EXTERNAL_ID_PREFIXES = {
      "pages" => "pages:",
      "blogs" => "blogs:"
    }.freeze

    module_function

    def canonical_pod_type?(value)
      value.to_s == CANONICAL_POD_TYPE
    end

    def legacy_pod_type?(value)
      LEGACY_POD_TYPES.include?(value.to_s)
    end

    def pod_type(value)
      legacy_pod_type?(value) ? CANONICAL_POD_TYPE : value.to_s
    end

    def external_id(source_type, record_id)
      normalized_source_type = source_type.to_s
      prefix = SOURCE_EXTERNAL_ID_PREFIXES[normalized_source_type] || registered_source_prefix(normalized_source_type)
      raise ArgumentError, "Unknown Mosaic Relay source: #{source_type}" unless prefix
      identifier = record_id.to_s
      raise ArgumentError, "A Mosaic Relay record ID is required" if identifier.empty?

      "#{prefix}#{identifier}"
    end

    def registered_source_prefix(source_type)
      return unless defined?(MosaicRelay::SourceRegistry)

      source = MosaicRelay::SourceRegistry.fetch(source_type)
      "#{source.key}:" if source
    end
  end
end

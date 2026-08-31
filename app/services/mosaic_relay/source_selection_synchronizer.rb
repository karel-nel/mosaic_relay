# frozen_string_literal: true

module MosaicRelay
  # Turns a saved Settings change into Relay feed events. This keeps source
  # selection changes observable to Relay's incremental cursor rather than
  # waiting for each record to be edited again.
  class SourceSelectionSynchronizer
    def self.call(previous_source_types:, previous_field_mappings:, relay_setting:)
      new(previous_source_types:, previous_field_mappings:, relay_setting:).call
    end

    def initialize(previous_source_types:, previous_field_mappings:, relay_setting:)
      @previous_source_types = Array(previous_source_types)
      @previous_field_mappings = previous_field_mappings || {}
      @relay_setting = relay_setting
    end

    def call
      disabled_sources.each { |source_key| ChangeRecorder.record_source_tombstones(source_key) }
      refreshed_sources.each { |source_key| ChangeRecorder.record_source_documents(source_key) }
    end

    private

    attr_reader :previous_source_types, :previous_field_mappings, :relay_setting

    def current_source_types
      @current_source_types ||= Array(relay_setting.source_types)
    end

    def disabled_sources
      previous_source_types - current_source_types
    end

    def refreshed_sources
      enabled_sources + field_changed_sources
    end

    def enabled_sources
      current_source_types - previous_source_types
    end

    def field_changed_sources
      (previous_source_types & current_source_types).select do |source_key|
        previous_field_mappings[source_key] != relay_setting.source_field_mappings[source_key]
      end
    end
  end
end

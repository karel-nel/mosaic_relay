# frozen_string_literal: true

require "uri"

module MosaicRelay
  # The singleton, database-backed configuration for the Relay integration.
  class RelaySetting < ApplicationRecord
    self.table_name = "mosaic_relay_settings"

    serialize :source_types, coder: YAML, type: Array
    serialize :source_field_mappings, coder: YAML, type: Hash

    def source_types
      values = super
      values = SourceRegistry.default_source_types if values.nil?
      Array(values).map(&:to_s) & SourceRegistry.keys
    end

    def source_types=(values)
      super(Array(values).map(&:to_s) & SourceRegistry.keys)
    end

    def source_field_mappings
      SourceRegistry.normalize_field_mappings(super || {})
    end

    def source_field_mappings=(values)
      super(SourceRegistry.normalize_field_mappings(values))
    end

    def self.current
      raise ActiveRecord::StatementInvalid, "mosaic_relay_settings has not been migrated" unless table_available?

      first || create!(default_attributes)
    end

    def self.table_available?
      connection.data_source_exists?(table_name)
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
      false
    end

    def self.default_attributes
      {
        default_language: Configuration::DEFAULT_LANGUAGE,
        page_size: Configuration::DEFAULT_PAGE_SIZE,
        widget_markup: "",
        source_types: SourceRegistry.default_source_types,
        source_field_mappings: {}
      }
    end

    validates :default_language, presence: true
    validates :page_size, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 250 }
    validate :public_base_url_must_be_absolute

    private

    def public_base_url_must_be_absolute
      return if public_base_url.blank?

      uri = URI.parse(public_base_url)
      return if uri.is_a?(URI::HTTP) && uri.host.present?

      errors.add(:public_base_url, "must be an absolute HTTP(S) URL")
    rescue URI::InvalidURIError
      errors.add(:public_base_url, "must be an absolute HTTP(S) URL")
    end
  end
end

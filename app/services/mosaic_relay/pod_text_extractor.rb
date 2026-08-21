# frozen_string_literal: true

module MosaicRelay
  class PodTextExtractor
    NON_INDEXABLE_POD_TYPES = %w[
      button_link_bar code_injection_pod gallery_pod image_widget insta_pod instagram_feed page_line_spacer
    ].freeze
    NON_CONTENT_KEYS = /\A(?:accept|attachment_key|bg_image|button_text|classes?|content_type|css_content|filename|html_content|icon|image|js_content|placement|src|svg_icon|url)\z/i
    SCALAR_TYPES = %w[text rich_text select email url date number integer].freeze

    def initialize(schema_resolver: MosaicRelay.configuration.pod_schema_resolver)
      @schema_resolver = schema_resolver
    end

    def call(pod_type:, definition:)
      return "" if NON_INDEXABLE_POD_TYPES.include?(pod_type.to_s)
      return "" unless definition.is_a?(Hash)

      text = extract_hash(definition.deep_stringify_keys, schema_for(pod_type))
      PlainText.clean(text)
    end

    def content_blocks(pod_type:, definition:)
      return [] if NON_INDEXABLE_POD_TYPES.include?(pod_type.to_s)
      return [] unless definition.is_a?(Hash)

      extract_block_hash(definition.deep_stringify_keys, schema_for(pod_type))
    end

    private

    def schema_for(pod_type)
      resolved = if @schema_resolver.respond_to?(:call)
        @schema_resolver.call(pod_type)
      elsif defined?(::Admin::PodSchemas) && ::Admin::PodSchemas.respond_to?(:schema_for)
        ::Admin::PodSchemas.schema_for(pod_type, include_inactive: true)
      elsif defined?(::PodDefinition) && ::PodDefinition.respond_to?(:find_by)
        ::PodDefinition.find_by(pod_type: pod_type)&.schema
      end

      schema = resolved.to_h
      nested_schema = schema["schema"] || schema[:schema]
      nested_schema.is_a?(Hash) ? nested_schema : schema
    end

    def extract_hash(values, schema)
      ordered_fields(schema).filter_map do |key, config|
        next if key.match?(NON_CONTENT_KEYS)
        next unless values.key?(key)

        value = extract_value(values[key], config.to_h)
        next if value.blank?

        label = config.to_h["label"].presence || key.humanize
        "#{label}: #{value}"
      end.join("\n\n")
    end

    def extract_value(value, config)
      type = config["type"].to_s
      return "" if value.nil? || value == false

      case type
      when *SCALAR_TYPES
        scalar_text(value)
      when "image"
        image_alt_text(value)
      when "object"
        extract_hash(value.to_h.deep_stringify_keys, config["schema"].to_h)
      when "array"
        Array(value).filter_map { |item| extract_hash(item.to_h.deep_stringify_keys, config["item_schema"].to_h).presence }.join("\n\n")
      else
        scalar_text(value)
      end
    end

    def extract_block_hash(values, schema)
      ordered_fields(schema).flat_map do |key, config|
        next [] if key.match?(NON_CONTENT_KEYS)
        next [] unless values.key?(key)

        extract_blocks_for_value(values[key], config.to_h, key)
      end
    end

    def extract_blocks_for_value(value, config, key)
      type = config["type"].to_s
      return [] if value.nil? || value == false

      case type
      when "rich_text"
        ContentBlockExtractor.from_html(value)
      when "object"
        extract_block_hash(value.to_h.deep_stringify_keys, config["schema"].to_h)
      when "array"
        Array(value).flat_map { |item| extract_block_hash(item.to_h.deep_stringify_keys, config["item_schema"].to_h) }
      when "image"
        text = image_alt_text(value)
        text.present? ? [ { "kind" => "paragraph", "text" => text } ] : []
      else
        text = scalar_text(value)
        return [] if text.blank?

        label = config["label"].presence || key.humanize
        [ { "kind" => "paragraph", "text" => "#{label}: #{text}" } ]
      end
    end

    def scalar_text(value)
      case value
      when String then PlainText.clean(value)
      when Numeric then value.to_s
      when Hash, Array then extract_editor_text(value)
      else ""
      end
    end

    def image_alt_text(value)
      return "" unless value.is_a?(Hash)

      PlainText.clean(value["alt_text"] || value[:alt_text] || value["alt"] || value[:alt])
    end

    def extract_editor_text(value)
      case value
      when Hash
        direct_text = value["text"] || value[:text]
        return PlainText.clean(direct_text) if direct_text.is_a?(String)

        value.values.filter_map { |child| extract_editor_text(child).presence }.join(" ")
      when Array
        value.filter_map { |child| extract_editor_text(child).presence }.join(" ")
      else
        ""
      end
    end

    def ordered_fields(schema)
      return [] unless schema.is_a?(Hash)

      schema.sort_by do |field_name, field_config|
        position = field_config.is_a?(Hash) ? field_config["position"] || field_config[:position] : nil
        parsed_position = Integer(position) rescue nil
        [ parsed_position || Float::INFINITY, field_name.to_s ]
      end
    end
  end
end

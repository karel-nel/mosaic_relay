# frozen_string_literal: true

require "digest"
require "set"

module MosaicRelay
  class PageContentExtractor
    Result = Struct.new(:content, :content_blocks, :assets, :updated_at, :pod_types, :component_count, keyword_init: true)

    def initialize(page, pod_schema_resolver: MosaicRelay.configuration.pod_schema_resolver,
                   asset_url_builder: MosaicRelay.configuration.asset_url_builder)
      @page = page
      @pod_text_extractor = PodTextExtractor.new(schema_resolver: pod_schema_resolver)
      @asset_url_builder = asset_url_builder || default_asset_url_builder
      @timestamps = [ page.updated_at ]
      @pod_types = []
      @component_count = 0
      @content_blocks = []
      @assets = []
      @asset_external_ids = Set.new
    end

    def call
      body = section_builder_page? ? section_content : legacy_pod_content
      content = [ "Title: #{page.title}", page.meta_description.presence && "Description: #{PlainText.clean(page.meta_description)}", body.presence ].compact.join("\n\n")

      Result.new(
        content: PlainText.clean(content),
        content_blocks: @content_blocks,
        assets: @assets,
        updated_at: @timestamps.compact.max || page.updated_at,
        pod_types: @pod_types.uniq.sort,
        component_count: @component_count
      )
    end

    private

    attr_reader :page

    def legacy_pod_content
      legacy_page_pods.filter_map do |page_pod|
        @timestamps.concat([ page_pod.updated_at, page_pod.pod.updated_at ])
        extract_pod(page_pod.pod, page_pod_definition(page_pod))
      end.join("\n\n")
    end

    def section_builder_page?
      page.respond_to?(:sections?) && page.sections?
    end

    def legacy_page_pods
      relation = page.page_pods
      relation = relation.visible if relation.respond_to?(:visible)
      relation = relation.includes(:pod) if relation.respond_to?(:includes)

      if relation.respond_to?(:ordered_by_position)
        relation.ordered_by_position
      elsif relation.respond_to?(:order)
        relation.order(:position)
      else
        Array(relation).sort_by(&:position)
      end
    end

    def page_pod_definition(page_pod)
      return page_pod.live_definition if page_pod.respond_to?(:live_definition)
      return page_pod.merged_definition if page_pod.respond_to?(:merged_definition)

      page_pod.pod.definition
    end

    def section_content
      composition = page.page_compositions.find_by(state: "published")
      return "" if composition.blank?

      @timestamps << composition.updated_at
      composition.page_sections.includes(page_section_slots: { page_elements: [ :element_contract, :pod ] }).order(:position).filter_map do |section|
        @timestamps << section.updated_at
        section.page_section_slots.sort_by(&:position).filter_map do |slot|
          @timestamps << slot.updated_at
          slot.page_elements.sort_by(&:position).filter_map { |element| extract_element(element) }
        end.join("\n\n").presence
      end.join("\n\n")
    end

    def extract_element(element)
      @timestamps << element.updated_at
      @component_count += 1

      case element.element_contract&.key
      when "heading"
        text = PlainText.clean(element.content["text"])
        @content_blocks << { "kind" => "heading", "level" => heading_level(element), "text" => text } if text.present?
        text
      when "text"
        body = element.content["body"]
        @content_blocks.concat(ContentBlockExtractor.from_html(body))
        PlainText.clean(body)
      when "image"
        image = element.content.to_h.deep_stringify_keys
        alt_text = PlainText.clean(image["alt"] || image.dig("image", "alt"))
        @content_blocks << { "kind" => "paragraph", "text" => alt_text } if alt_text.present?
        append_element_asset(element, image, alt_text)
        alt_text
      when "pod_embed"
        return "" if element.pod.blank?

        definition = element.pod.definition.to_h.deep_stringify_keys.deep_merge(element.content.to_h.fetch("pod_definition_override", {}).to_h.deep_stringify_keys)
        @timestamps << element.pod.updated_at
        extract_pod(element.pod, definition)
      else
        ""
      end
    end

    def extract_pod(pod, definition)
      @component_count += 1
      @pod_types << pod.pod_type.to_s
      append_pod_assets(pod, definition)
      @content_blocks.concat(@pod_text_extractor.content_blocks(pod_type: pod.pod_type, definition: definition))
      @pod_text_extractor.call(pod_type: pod.pod_type, definition: definition)
    end

    def heading_level(element)
      level = element.settings.to_h["level"].to_s.delete_prefix("h").to_i
      level.between?(1, 6) ? level : 2
    end

    def append_element_asset(element, image, alt_text)
      url = image["src"].presence || image.dig("image", "url").presence
      return unless url.to_s.match?(%r{\Ahttps://}i)

      mime_type = image["content_type"].presence || image.dig("image", "content_type").presence
      return if mime_type.blank?

      append_asset({
        "external_id" => "page-elements:#{element.id}:image",
        "kind" => "image",
        "url" => url,
        "mime_type" => mime_type,
        "content_hash" => Digest::SHA256.hexdigest([ url, mime_type, alt_text ].join("\u0000")),
        "alt_text" => alt_text.presence
      }.compact)
    end

    def append_pod_assets(pod, definition)
      return unless defined?(::ActiveStorage::Attachment)
      return unless @asset_url_builder.respond_to?(:call)

      ::ActiveStorage::Attachment.where(record: pod).includes(:blob).find_each do |attachment|
        blob = attachment.blob
        next unless blob.content_type.to_s.start_with?("image/")

        url = @asset_url_builder.call(blob)
        next if url.blank?

        append_asset({
          "external_id" => "active-storage-blobs:#{blob.id}",
          "kind" => "image",
          "url" => url,
          "mime_type" => blob.content_type,
          "content_hash" => asset_fingerprint(blob.key, blob.checksum, blob.byte_size, blob.content_type),
          "alt_text" => attachment_alt_text(definition, attachment.name).presence
        }.compact)
      end
    end

    def attachment_alt_text(value, attachment_key)
      case value
      when Hash
        hash = value.deep_stringify_keys
        return PlainText.clean(hash["alt_text"] || hash["alt"]) if hash["attachment_key"] == attachment_key

        hash.each_value do |child|
          alt_text = attachment_alt_text(child, attachment_key)
          return alt_text if alt_text.present?
        end
      when Array
        value.each do |child|
          alt_text = attachment_alt_text(child, attachment_key)
          return alt_text if alt_text.present?
        end
      end
      ""
    end

    def append_asset(asset)
      return if @asset_external_ids.include?(asset.fetch("external_id"))

      @asset_external_ids << asset.fetch("external_id")
      @assets << asset
    end

    def asset_fingerprint(*parts)
      Digest::SHA256.hexdigest(parts.join("\u0000"))
    end

    def default_asset_url_builder
      return unless defined?(::Settings) && ::Settings.respond_to?(:bunny)

      ->(blob) { "#{::Settings.bunny.cdn}/#{blob.key}" }
    end
  end
end

# frozen_string_literal: true

require "digest"
require "json"
require "uri"

module MosaicRelay
  class DocumentSerializer
    class << self
      def for_page(page, fields: nil, public_base_url: nil)
        return unless page&.published?

        extracted = PageContentExtractor.new(page).call
        return if extracted.content.blank?
        selected_fields = source_fields(fields, default: %w[content menu_title meta_description])
        full_document = selected_fields.nil? || selected_fields.sort == %w[content menu_title meta_description]
        content_blocks = full_document ? page_content_blocks(page, extracted) : selected_page_content_blocks(page, extracted, selected_fields)
        content = full_document ? extracted.content : content_from_blocks(content_blocks)
        return if content.blank?

        document(
          external_id: MigrationContract.external_id("pages", page.id),
          title: page.title,
          url: page_url(page, public_base_url),
          content: content,
          content_blocks: content_blocks,
          content_type: "page",
          updated_at: extracted.updated_at,
          metadata: {
            source: "mosaic_cms",
            page_id: page.id,
            slug: page.slug,
            canonical_path: page_path(page),
            builder_mode: (page.builder_mode if page.respond_to?(:builder_mode)),
            published_at: iso8601(page.published_at),
            meta_description: (PlainText.clean(page.meta_description) if full_document || selected_fields.include?("meta_description")),
            menu_title: (page.menu_title if full_document || selected_fields.include?("menu_title")),
            show_in_menu: page.show_in_menu,
            show_in_footer: page.show_in_footer,
            ancestry: page.ancestry,
            pod_types: extracted.pod_types,
            content_component_count: extracted.component_count,
            assets: extracted.assets
          }
        )
      end

      def for_blog(blog, fields: nil, public_base_url: nil)
        return unless blog&.displayable?

        selected_fields = source_fields(fields, default: %w[content excerpt seo_description seo_title])
        full_document = selected_fields.nil? || selected_fields.sort == %w[content excerpt seo_description seo_title]
        body = PlainText.clean(blog.content_plain_text)
        return if body.blank? && (full_document || selected_fields.include?("content"))

        categories = blog_categories(blog).map { |category| taxonomy(category) }
        tags = ordered_blog_tags(blog).map { |tag| taxonomy(tag) }
        content = [
          "Title: #{blog.title}",
          blog.excerpt.presence && "Summary: #{PlainText.clean(blog.excerpt)}",
          body
        ].compact.join("\n\n")
        content_blocks = [
          { "kind" => "heading", "level" => 1, "text" => blog.title },
          ({ "kind" => "paragraph", "text" => PlainText.clean(blog.excerpt) } if blog.excerpt.present?),
          *ContentBlockExtractor.from_html(blog.content&.body&.to_html || body)
        ].compact
        unless full_document
          content, content_blocks = selected_blog_content(blog, body, selected_fields)
          return if content.blank?
        end
        updated_at = [
          blog.updated_at,
          blog.content&.updated_at,
          *association_timestamps(blog, :blog_taggings),
          *association_timestamps(blog, :blog_category_assignments)
        ].compact.max

        document(
          external_id: MigrationContract.external_id("blogs", blog.id),
          title: blog.title,
          url: blog_url(blog, public_base_url),
          content: content,
          content_blocks: content_blocks,
          content_type: "article",
          updated_at: updated_at,
          metadata: {
            source: "mosaic_cms",
            blog_id: blog.id,
            slug: blog.slug,
            display_title: blog.display_title,
            legacy_post_id: optional_attribute(blog, :legacy_post_id),
            legacy_slug: optional_attribute(blog, :legacy_slug),
            author: blog.author_name,
            excerpt: (PlainText.clean(blog.excerpt) if full_document || selected_fields.include?("excerpt")),
            seo_title: (blog.seo_title if full_document || selected_fields.include?("seo_title")),
            seo_description: (PlainText.clean(blog.seo_description) if full_document || selected_fields.include?("seo_description")),
            published_at: iso8601(blog.published_at),
            created_at: iso8601(blog.created_at),
            categories: categories,
            tags: tags,
            legacy_paths: legacy_paths(blog),
            cover_image: cover_image_metadata(blog),
            assets: cover_image_asset(blog),
            word_count: body.split.size
          }
        )
      end

      # Registered Mosaic sources use the same canonical Relay document shape
      # as Pages and Blogs. The registry controls the title, fields, and
      # public record path; callers cannot pass arbitrary model attributes.
      def for_source(record, source, fields: nil, public_base_url: nil)
        return unless record && source
        return for_page(record, fields: fields, public_base_url: public_base_url) if source.key == "pages"
        return for_blog(record, fields: fields, public_base_url: public_base_url) if source.key == "blogs"

        title = source_title(record, source)
        selected_fields = Array(fields).filter_map do |field|
          next unless record.respond_to?(field)

          text = PlainText.clean(record.public_send(field))
          [ field.to_s.humanize, text ] if text.present?
        end
        path = source.public_path_for(record)
        return if path.blank?

        content = ([ "Title: #{title}" ] + selected_fields.map { |label, text| "#{label}: #{text}" }).join("\n\n")
        document(
          external_id: MigrationContract.external_id(source.key, record.id),
          title: title,
          url: source_url(path, public_base_url),
          content: content,
          content_blocks: source_content_blocks(title, selected_fields),
          content_type: source.content_type.presence || source.key.singularize,
          updated_at: source_updated_at(record),
          metadata: {
            source: "mosaic_cms",
            source_type: source.key,
            record_id: record.id,
            canonical_path: path
          }
        )
      end

      def for_change(change, fields: nil, public_base_url: nil)
        document = case change.resource_type
        when "Page" then for_page(find_page(change.resource_id), fields: fields, public_base_url: public_base_url)
        when "Blog" then for_blog(find_blog(change.resource_id), fields: fields, public_base_url: public_base_url)
        end

        document || { "external_id" => change.external_id, "deleted" => true }
      end

      private

      def document(external_id:, title:, url:, content:, content_blocks:, content_type:, updated_at:, metadata:)
        return if url.blank?

        cleaned_content = PlainText.clean(content)
        cleaned_blocks = content_blocks.filter_map { |block| normalize_block(block) }
        cleaned_metadata = metadata.compact.deep_stringify_keys
        {
          "external_id" => external_id,
          "title" => title.to_s,
          "url" => url,
          "content" => cleaned_content,
          "content_type" => content_type,
          "language" => configuration.default_language,
          "updated_at" => iso8601(updated_at),
          "content_hash" => content_hash(content: cleaned_content, content_blocks: cleaned_blocks, metadata: cleaned_metadata),
          "deleted" => false,
          "content_blocks" => cleaned_blocks,
          "metadata" => cleaned_metadata
        }
      end

      def page_path(page)
        page.slug == "home" ? "/" : "/#{ERB::Util.url_encode(page.slug)}"
      end

      def source_fields(fields, default:)
        return if fields.nil?

        Array(fields).map(&:to_s) & default
      end

      def selected_page_content_blocks(page, extracted, selected_fields)
        blocks = [ { "kind" => "heading", "level" => 1, "text" => page.title } ]
        if selected_fields.include?("meta_description") && page.meta_description.present?
          blocks << { "kind" => "paragraph", "text" => PlainText.clean(page.meta_description) }
        end
        blocks.concat(extracted.content_blocks) if selected_fields.include?("content")
        if selected_fields.include?("menu_title") && page.menu_title.present?
          blocks << { "kind" => "paragraph", "text" => "Menu title: #{page.menu_title}" }
        end
        blocks
      end

      def selected_blog_content(blog, body, selected_fields)
        sections = [ "Title: #{blog.title}" ]
        blocks = [ { "kind" => "heading", "level" => 1, "text" => blog.title } ]
        add_selected_blog_section(sections, blocks, "Summary", PlainText.clean(blog.excerpt), selected_fields.include?("excerpt"))
        add_selected_blog_section(sections, blocks, "Content", body, selected_fields.include?("content"))
        add_selected_blog_section(sections, blocks, "SEO title", blog.seo_title, selected_fields.include?("seo_title"))
        add_selected_blog_section(sections, blocks, "SEO description", PlainText.clean(blog.seo_description), selected_fields.include?("seo_description"))

        [ sections.join("\n\n"), blocks ]
      end

      def add_selected_blog_section(sections, blocks, label, value, selected)
        return unless selected && value.present?

        sections << "#{label}: #{value}"
        blocks << { "kind" => "heading", "level" => 2, "text" => label }
        blocks << { "kind" => "paragraph", "text" => value }
      end

      def content_from_blocks(blocks)
        Array(blocks).filter_map do |block|
          case block["kind"]
          when "heading", "paragraph", "table", "code" then PlainText.clean(block["text"])
          when "list" then Array(block["items"]).map { |item| PlainText.clean(item) }.compact.join("\n")
          end
        end.join("\n\n")
      end

      def source_title(record, source)
        value = record.public_send(source.title) if source.title.present? && record.respond_to?(source.title)
        PlainText.clean(value).presence || "Untitled #{source.label.to_s.singularize}"
      end

      def source_url(path, public_base_url)
        absolute_url(path, public_base_url)
      end

      def source_content_blocks(title, fields)
        [ { "kind" => "heading", "level" => 1, "text" => title } ] + fields.flat_map do |label, value|
          [
            { "kind" => "heading", "level" => 2, "text" => label },
            { "kind" => "paragraph", "text" => value }
          ]
        end
      end

      def source_updated_at(record)
        timestamps = []
        timestamps << record.updated_at if record.respond_to?(:updated_at)
        timestamps << record.published_at if record.respond_to?(:published_at)
        timestamps.compact.max || Time.current
      end

      def page_url(page, public_base_url)
        absolute_url(page_path(page), public_base_url)
      end

      def blog_url(blog, public_base_url)
        path = if configuration.blog_path_builder.respond_to?(:call)
          configuration.blog_path_builder.call(blog)
        else
          default_blog_path(blog)
        end

        absolute_url(path, public_base_url)
      end

      def default_blog_path(blog)
        return unless defined?(Rails) && Rails.application

        routes = Rails.application.routes.url_helpers
        return routes.blog_path(blog) if routes.respond_to?(:blog_path)

        "/blogs/#{ERB::Util.url_encode(blog.slug)}"
      rescue StandardError
        "/blogs/#{ERB::Util.url_encode(blog.slug)}"
      end

      def absolute_url(path, public_base_url)
        raw_path = path.to_s
        candidate = if raw_path.match?(%r{\Ahttps?://}i)
          raw_path
        else
          base_url = public_base_url.to_s.strip.presence || configuration.public_base_url
          base_url = base_url.to_s.sub(%r{/+\z}, "")
          return if base_url.blank?

          "#{base_url}#{raw_path.start_with?("/") ? raw_path : "/#{raw_path}"}"
        end

        [ candidate, URI::DEFAULT_PARSER.escape(candidate) ].uniq.each do |value|
          uri = URI.parse(value)
          return uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
        rescue URI::InvalidURIError
          next
        end

        nil
      rescue URI::InvalidURIError
        nil
      end

      def blog_categories(blog)
        if blog.respond_to?(:category_records)
          Array(blog.category_records)
        elsif blog.respond_to?(:blog_categories)
          Array(blog.blog_categories)
        elsif blog.respond_to?(:blog_category)
          [ blog.blog_category ].compact
        else
          []
        end
      end

      def ordered_blog_tags(blog)
        return [] unless blog.respond_to?(:blog_tags)

        tags = blog.blog_tags
        tags = tags.order(:name) if tags.respond_to?(:order)
        Array(tags)
      end

      def association_timestamps(record, association)
        return [] unless record.respond_to?(association)

        Array(record.public_send(association)).filter_map { |item| item.updated_at if item.respond_to?(:updated_at) }
      end

      def legacy_paths(blog)
        return [] unless blog.respond_to?(:blog_legacy_redirects)

        redirects = blog.blog_legacy_redirects
        redirects = redirects.active if redirects.respond_to?(:active)
        redirects = redirects.order(:legacy_path) if redirects.respond_to?(:order)

        if redirects.respond_to?(:pluck)
          redirects.pluck(:legacy_path)
        else
          Array(redirects).filter_map { |redirect| redirect.legacy_path if redirect.respond_to?(:legacy_path) }
        end
      end

      def optional_attribute(record, attribute)
        record.public_send(attribute) if record.respond_to?(attribute)
      end

      def taxonomy(record)
        { id: record.id, name: record.name, slug: record.slug }
      end

      def cover_image_metadata(blog)
        return unless blog.respond_to?(:cover_image)
        return unless blog.cover_image.attached?

        blob = blog.cover_image.blob
        { filename: blob.filename.to_s, content_type: blob.content_type, byte_size: blob.byte_size }
      end

      def cover_image_asset(blog)
        return [] unless blog.respond_to?(:cover_image)
        return [] unless blog.cover_image.attached?
        return [] unless asset_url_builder.respond_to?(:call)

        blob = blog.cover_image.blob
        url = asset_url_builder.call(blob)
        return [] if url.blank?

        [ {
          "external_id" => "active-storage-blobs:#{blob.id}",
          "kind" => "image",
          "url" => url,
          "mime_type" => blob.content_type,
          "content_hash" => Digest::SHA256.hexdigest([ blob.key, blob.checksum, blob.byte_size, blob.content_type ].join("\u0000"))
        }.compact ]
      end

      def page_content_blocks(page, extracted)
        [
          { "kind" => "heading", "level" => 1, "text" => page.title },
          ({ "kind" => "paragraph", "text" => PlainText.clean(page.meta_description) } if page.meta_description.present?),
          *extracted.content_blocks
        ].compact
      end

      def normalize_block(block)
        kind = block["kind"].to_s
        case kind
        when "heading"
          text = PlainText.clean(block["text"])
          return if text.blank?

          { "kind" => kind, "level" => block["level"].to_i.clamp(1, 6), "text" => text }
        when "paragraph", "table", "code"
          text = PlainText.clean(block["text"])
          return if text.blank?

          { "kind" => kind, "text" => text }
        when "list"
          items = Array(block["items"]).filter_map { |item| PlainText.clean(item).presence }
          return if items.blank?

          { "kind" => kind, "items" => items }
        when "page_break"
          page = block["page"].to_i
          return unless page.positive?

          { "kind" => kind, "page" => page }
        end
      end

      def content_hash(content:, content_blocks:, metadata:)
        canonical = canonicalize("content" => content, "content_blocks" => content_blocks, "metadata" => metadata)
        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      def canonicalize(value)
        case value
        when Hash
          value.to_h.sort_by { |key, _child| key.to_s }.to_h { |key, child| [ key.to_s, canonicalize(child) ] }
        when Array
          value.map { |item| canonicalize(item) }
        else
          value
        end
      end

      def iso8601(time)
        time&.utc&.iso8601
      end

      def find_page(id)
        page_model&.find_by(id: id)
      end

      def find_blog(id)
        model = blog_model
        return unless model

        relation = model
        associations = blog_association_names(model)
        relation = relation.includes(*associations) if relation.respond_to?(:includes) && associations.any?
        relation = relation.with_rich_text_content if relation.respond_to?(:with_rich_text_content)
        relation.find_by(id: id)
      end

      def page_model
        configuration.page_model || (defined?(::Page) ? ::Page : nil)
      end

      def blog_model
        configuration.blog_model || (defined?(::Blog) ? ::Blog : nil)
      end

      def asset_url_builder
        configuration.asset_url_builder || default_asset_url_builder
      end

      def configuration
        MosaicRelay.configuration
      end

      def default_asset_url_builder
        return unless defined?(::Settings) && ::Settings.respond_to?(:bunny)

        ->(blob) { "#{::Settings.bunny.cdn}/#{blob.key}" }
      end

      def blog_association_names(model)
        return [] unless model.respond_to?(:reflect_on_association)

        %i[
          blog_category blog_categories blog_tags blog_taggings
          blog_category_assignments blog_legacy_redirects
        ].select { |name| model.reflect_on_association(name) }
      end
    end
  end
end

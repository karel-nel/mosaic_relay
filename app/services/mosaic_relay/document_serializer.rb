# frozen_string_literal: true

require "digest"
require "json"

module MosaicRelay
  class DocumentSerializer
    class << self
      def for_page(page)
        return unless page&.published?

        extracted = PageContentExtractor.new(page).call
        return if extracted.content.blank?

        document(
          external_id: "pages:#{page.id}",
          title: page.title,
          url: page_url(page),
          content: extracted.content,
          content_blocks: page_content_blocks(page, extracted),
          content_type: "page",
          updated_at: extracted.updated_at,
          metadata: {
            source: "mosaic_cms",
            page_id: page.id,
            slug: page.slug,
            canonical_path: page_path(page),
            builder_mode: page.builder_mode,
            published_at: iso8601(page.published_at),
            meta_description: PlainText.clean(page.meta_description),
            menu_title: page.menu_title,
            show_in_menu: page.show_in_menu,
            show_in_footer: page.show_in_footer,
            ancestry: page.ancestry,
            pod_types: extracted.pod_types,
            content_component_count: extracted.component_count,
            assets: extracted.assets
          }
        )
      end

      def for_blog(blog)
        return unless blog&.displayable?

        body = PlainText.clean(blog.content_plain_text)
        return if body.blank?

        categories = blog.category_records.map { |category| taxonomy(category) }
        tags = blog.blog_tags.order(:name).map { |tag| taxonomy(tag) }
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
        updated_at = [ blog.updated_at, blog.content&.updated_at, *blog.blog_taggings.map(&:updated_at), *blog.blog_category_assignments.map(&:updated_at) ].compact.max

        document(
          external_id: "blogs:#{blog.id}",
          title: blog.title,
          url: "#{configuration.public_base_url}/blogs/#{ERB::Util.url_encode(blog.slug)}",
          content: content,
          content_blocks: content_blocks,
          content_type: "article",
          updated_at: updated_at,
          metadata: {
            source: "mosaic_cms",
            blog_id: blog.id,
            slug: blog.slug,
            display_title: blog.display_title,
            legacy_post_id: blog.legacy_post_id,
            legacy_slug: blog.legacy_slug,
            author: blog.author_name,
            excerpt: PlainText.clean(blog.excerpt),
            seo_title: blog.seo_title,
            seo_description: PlainText.clean(blog.seo_description),
            published_at: iso8601(blog.published_at),
            created_at: iso8601(blog.created_at),
            categories: categories,
            tags: tags,
            legacy_paths: blog.blog_legacy_redirects.active.order(:legacy_path).pluck(:legacy_path),
            cover_image: cover_image_metadata(blog),
            assets: cover_image_asset(blog),
            word_count: body.split.size
          }
        )
      end

      def for_change(change)
        document = case change.resource_type
        when "Page" then for_page(find_page(change.resource_id))
        when "Blog" then for_blog(find_blog(change.resource_id))
        end

        document || { "external_id" => change.external_id, "deleted" => true }
      end

      private

      def document(external_id:, title:, url:, content:, content_blocks:, content_type:, updated_at:, metadata:)
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

      def page_url(page)
        "#{configuration.public_base_url}#{page_path(page)}"
      end

      def taxonomy(record)
        { id: record.id, name: record.name, slug: record.slug }
      end

      def cover_image_metadata(blog)
        return unless blog.cover_image.attached?

        blob = blog.cover_image.blob
        { filename: blob.filename.to_s, content_type: blob.content_type, byte_size: blob.byte_size }
      end

      def cover_image_asset(blog)
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
        relation = relation.includes(:blog_category, :blog_categories, :blog_tags, :blog_taggings, :blog_category_assignments, :blog_legacy_redirects) if relation.respond_to?(:includes)
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
    end
  end
end

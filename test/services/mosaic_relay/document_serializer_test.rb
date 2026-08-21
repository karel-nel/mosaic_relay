# frozen_string_literal: true

require "test_helper"

class MosaicRelayDocumentSerializerTest < ActiveSupport::TestCase
  Collection = Class.new(Array) do
    def order(attribute)
      sort_by { |record| record.public_send(attribute) }
    end

    def active
      self
    end

    def pluck(attribute)
      map { |record| record.public_send(attribute) }
    end
  end

  Attachment = Struct.new(:attached_value) do
    def attached?
      attached_value
    end
  end

  Category = Struct.new(:id, :name, :slug)
  Tag = Struct.new(:id, :name, :slug)
  Redirect = Struct.new(:legacy_path)
  Page = Struct.new(
    :id, :title, :slug, :meta_description, :published_value, :published_at, :builder_mode,
    :menu_title, :show_in_menu, :show_in_footer, :ancestry,
    keyword_init: true
  ) do
    def published?
      published_value
    end
  end

  RichContent = Struct.new(:body, :updated_at)
  RichBody = Struct.new(:html) do
    def to_html
      html
    end
  end
  Blog = Struct.new(
    :id, :title, :slug, :excerpt, :displayable_value, :content_plain_text, :content,
    :updated_at, :published_at, :created_at, :legacy_post_id, :legacy_slug,
    :display_title, :author, :seo_title, :seo_description, :categories, :blog_tags,
    :blog_taggings, :blog_category_assignments, :blog_legacy_redirects, :cover_image,
    keyword_init: true
  ) do
    def displayable?
      displayable_value
    end

    def category_records
      categories
    end

    def author_name
      author
    end
  end

  Change = Struct.new(:resource_type, :resource_id, :external_id)

  setup do
    MosaicRelay.configure do |configuration|
      configuration.public_base_url = "https://mosaic.example/"
      configuration.default_language = "en-ZA"
    end
  end

  teardown do
    MosaicRelay.reset_configuration!
  end

  test "serializes a published page into the canonical document contract" do
    extracted = MosaicRelay::PageContentExtractor::Result.new(
      content: "Title: Race information\n\nRegistration opens at 08:00.",
      content_blocks: [
        { "kind" => "heading", "level" => 9, "text" => "Details" },
        { "kind" => "paragraph", "text" => "Registration opens at 08:00." },
        { "kind" => "list", "items" => [ "Bring ID", "" ] }
      ],
      assets: [],
      updated_at: Time.utc(2026, 8, 21, 10, 15),
      pod_types: [ "basic_text" ],
      component_count: 2
    )
    page = Page.new(
      id: 42,
      title: "Race information",
      slug: "race-information",
      meta_description: "Everything runners need",
      published_value: true,
      published_at: Time.utc(2026, 8, 20, 8),
      builder_mode: "pods",
      menu_title: "Race info",
      show_in_menu: true,
      show_in_footer: false,
      ancestry: nil
    )

    stub_class_method(MosaicRelay::PageContentExtractor, :new, ->(*) { Struct.new(:call).new(extracted) }) do
      document = MosaicRelay::DocumentSerializer.for_page(page)

      assert_equal "pages:42", document.fetch("external_id")
      assert_equal "https://mosaic.example/race-information", document.fetch("url")
      assert_equal "en-ZA", document.fetch("language")
      assert_equal [
        { "kind" => "heading", "level" => 1, "text" => "Race information" },
        { "kind" => "paragraph", "text" => "Everything runners need" },
        { "kind" => "heading", "level" => 6, "text" => "Details" },
        { "kind" => "paragraph", "text" => "Registration opens at 08:00." },
        { "kind" => "list", "items" => [ "Bring ID" ] }
      ], document.fetch("content_blocks")
      assert_equal [ "basic_text" ], document.dig("metadata", "pod_types")
      assert_match(/\A[a-f0-9]{64}\z/, document.fetch("content_hash"))
      assert_equal document, MosaicRelay::DocumentContract.validate!(document)
    end
  end

  test "serializes a published blog with taxonomy and rich-text blocks" do
    category = Category.new(1, "Race news", "race-news")
    tag = Tag.new(2, "Race day", "race-day")
    blog = Blog.new(
      id: 7,
      title: "Final race-day guide",
      slug: "final race-day guide",
      excerpt: "<p>Everything to know before race day.</p>",
      displayable_value: true,
      content_plain_text: "Collect your race number at the expo.",
      content: RichContent.new(RichBody.new("<h2>Race day</h2><p>Collect your race number at the expo.</p>"), Time.utc(2026, 8, 21, 10, 4)),
      updated_at: Time.utc(2026, 8, 21, 10),
      published_at: Time.utc(2026, 8, 20, 8),
      created_at: Time.utc(2026, 8, 19, 8),
      legacy_post_id: nil,
      legacy_slug: nil,
      display_title: "Final race-day guide",
      author: "Comrades Team",
      seo_title: "Race-day guide",
      seo_description: "A practical race-day guide.",
      categories: [ category ],
      blog_tags: Collection.new([ tag ]),
      blog_taggings: Collection.new,
      blog_category_assignments: Collection.new,
      blog_legacy_redirects: Collection.new([ Redirect.new("/old-race-guide") ]),
      cover_image: Attachment.new(false)
    )

    document = MosaicRelay::DocumentSerializer.for_blog(blog)

    assert_equal "blogs:7", document.fetch("external_id")
    assert_equal "https://mosaic.example/blogs/final%20race-day%20guide", document.fetch("url")
    assert_equal "article", document.fetch("content_type")
    assert_includes document.fetch("content"), "Collect your race number at the expo."
    assert_includes document.fetch("content_blocks"), { "kind" => "heading", "level" => 2, "text" => "Race day" }
    assert_equal [ { "id" => 1, "name" => "Race news", "slug" => "race-news" } ], document.dig("metadata", "categories")
    assert_equal [ { "id" => 2, "name" => "Race day", "slug" => "race-day" } ], document.dig("metadata", "tags")
    assert_equal [ "/old-race-guide" ], document.dig("metadata", "legacy_paths")
    assert_equal 7, document.dig("metadata", "word_count")
  end

  test "does not serialize a hidden or scheduled blog" do
    blog = Blog.new(
      id: 8,
      title: "Future race update",
      slug: "future-race-update",
      displayable_value: false,
      content_plain_text: "This is not public yet."
    )

    assert_nil MosaicRelay::DocumentSerializer.for_blog(blog)
  end

  test "returns a tombstone for an unknown or unsupported change" do
    change = Change.new("Page", 999, "pages:999")

    assert_equal({ "external_id" => "pages:999", "deleted" => true }, MosaicRelay::DocumentSerializer.for_change(change))
  end

  test "content hashes are stable when hash key insertion order changes" do
    first = MosaicRelay::DocumentSerializer.send(
      :content_hash,
      content: "Text",
      content_blocks: [],
      metadata: { "b" => 2, "a" => 1 }
    )
    second = MosaicRelay::DocumentSerializer.send(
      :content_hash,
      content: "Text",
      content_blocks: [],
      metadata: { "a" => 1, "b" => 2 }
    )

    assert_equal first, second
  end
end

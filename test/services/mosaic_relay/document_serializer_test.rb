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
    MosaicRelay::SourceRegistry.reset!
    MosaicRelay::RelaySetting.delete_all
    MosaicRelay::RelaySetting.current.update!(public_base_url: "https://mosaic.example/", default_language: "en-ZA")
  end

  teardown do
    MosaicRelay.reset_configuration!
    MosaicRelay::SourceRegistry.reset!
    MosaicRelay::RelaySetting.delete_all
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

  test "serializes a registered source using only its selected fields" do
    record = Struct.new(:id, :title, :summary, :body, :updated_at, keyword_init: true).new(
      id: 12,
      title: "Road closure",
      summary: "The north entrance is closed.",
      body: "Internal operations notes.",
      updated_at: Time.utc(2026, 8, 21, 12)
    )
    MosaicRelay.register_source(
      key: "announcements",
      label: "Announcements",
      model: record.class,
      title: :title,
      fields: %i[summary body],
      content_type: "announcement",
      collection_path: "/announcements",
      record_path: ->(announcement) { "/announcements/#{announcement.id}" }
    )
    source = MosaicRelay::SourceRegistry.fetch("announcements")

    document = MosaicRelay::DocumentSerializer.for_source(record, source, fields: [ :summary ])

    assert_equal "announcements:12", document.fetch("external_id")
    assert_equal "https://mosaic.example/announcements/12", document.fetch("url")
    assert_includes document.fetch("content"), "The north entrance is closed."
    refute_includes document.fetch("content"), "Internal operations notes."
    assert_equal document, MosaicRelay::DocumentContract.validate!(document)
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

  test "uses only selected Page fields when a source narrows the feed boundary" do
    extracted = MosaicRelay::PageContentExtractor::Result.new(
      content: "Title: Race information\n\nPrivate body",
      content_blocks: [ { "kind" => "paragraph", "text" => "Private body" } ],
      assets: [], updated_at: Time.utc(2026, 8, 21, 10), pod_types: [], component_count: 1
    )
    page = Page.new(id: 4, title: "Race information", slug: "race", meta_description: "Public summary", published_value: true)

    stub_class_method(MosaicRelay::PageContentExtractor, :new, ->(*) { Struct.new(:call).new(extracted) }) do
      document = MosaicRelay::DocumentSerializer.for_page(page, fields: [ :meta_description ])

      assert_includes document.fetch("content"), "Public summary"
      refute_includes document.fetch("content"), "Private body"
      assert_nil document.dig("metadata", "menu_title")
    end
  end

  test "uses only selected Blog fields when a source narrows the feed boundary" do
    blog = Blog.new(
      id: 10, title: "Update", slug: "update", excerpt: "Public summary", displayable_value: true,
      content_plain_text: "Private body", updated_at: Time.current, published_at: Time.current,
      created_at: Time.current, categories: [], blog_tags: Collection.new, blog_taggings: Collection.new,
      blog_category_assignments: Collection.new, blog_legacy_redirects: Collection.new, cover_image: Attachment.new(false)
    )

    document = MosaicRelay::DocumentSerializer.for_blog(blog, fields: [ :excerpt ])

    assert_includes document.fetch("content"), "Public summary"
    refute_includes document.fetch("content"), "Private body"
    assert_nil document.dig("metadata", "seo_title")
  end

  test "serializes a Merrell-style blog with a singular category and no legacy associations" do
    blog_class = Struct.new(
      :id, :title, :slug, :excerpt, :content_plain_text, :content, :updated_at,
      :published_at, :created_at, :blog_category, :blog_tags, :cover_image,
      keyword_init: true
    ) do
      def displayable? = true
      def display_title = title
      def author_name = "Merrell Team"
      def seo_title = nil
      def seo_description = nil
    end
    blog = blog_class.new(
      id: 9,
      title: "Trail running guide",
      slug: "trail-running-guide",
      excerpt: "What to bring.",
      content_plain_text: "Bring layers and water.",
      content: RichContent.new(RichBody.new("<p>Bring layers and water.</p>"), Time.utc(2026, 8, 21, 10, 4)),
      updated_at: Time.utc(2026, 8, 21, 10),
      published_at: Time.utc(2026, 8, 20, 8),
      created_at: Time.utc(2026, 8, 19, 8),
      blog_category: Category.new(3, "Advice", "advice"),
      blog_tags: Collection.new([ Tag.new(4, "Trail", "trail") ]),
      cover_image: Attachment.new(false)
    )
    MosaicRelay.configure do |configuration|
      configuration.blog_path_builder = ->(record) { "/blog/#{record.slug}" }
    end

    document = MosaicRelay::DocumentSerializer.for_blog(blog)

    assert_equal "https://mosaic.example/blog/trail-running-guide", document.fetch("url")
    assert_equal [ { "id" => 3, "name" => "Advice", "slug" => "advice" } ], document.dig("metadata", "categories")
    assert_equal [], document.dig("metadata", "legacy_paths")
    assert_not document.fetch("metadata").key?("legacy_post_id")
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

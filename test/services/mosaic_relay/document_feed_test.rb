# frozen_string_literal: true

require "test_helper"

class MosaicRelayDocumentFeedTest < ActiveSupport::TestCase
  Relation = Class.new do
    include Enumerable

    def initialize(records)
      @records = records
    end

    def each(&block)
      @records.each(&block)
    end

    def visible
      self.class.new(@records.select { |record| !record.respond_to?(:visible?) || record.visible? })
    end

    def published
      self.class.new(@records.select { |record| !record.respond_to?(:published?) || record.published? })
    end

    def where(_condition, last_id)
      self.class.new(@records.select { |record| record.id > last_id })
    end

    def includes(*)
      self
    end

    def with_rich_text_content
      self
    end

    def order(*)
      self.class.new(@records.sort_by(&:id))
    end

    def limit(count)
      self.class.new(@records.first(count))
    end

    def first
      @records.first
    end

    def to_a
      @records.dup
    end
  end

  Model = Class.new do
    class << self
      attr_accessor :records

      def published
        Relation.new(records).published
      end

      def visible
        Relation.new(records).visible
      end

      def all
        Relation.new(records)
      end

      def find_by(id:)
        Array(records).find { |record| record.id == id }
      end
    end
  end

  PageModel = Class.new(Model)
  BlogModel = Class.new(Model)
  AnnouncementModel = Class.new(Model)

  Record = Struct.new(:id, keyword_init: true)
  AnnouncementRecord = Struct.new(:id, :title, :summary, :private_notes, :updated_at, :published_value, keyword_init: true) do
    def published?
      published_value != false
    end
  end
  BlogRecord = Struct.new(:id, :visible_value, :published_at, keyword_init: true) do
    def visible?
      visible_value
    end

    def published?
      published_at.present? && published_at <= Time.current
    end
  end
  Change = Struct.new(:resource_type, :resource_id, :external_id)

  setup do
    MosaicRelay::SourceRegistry.reset!
    MosaicRelay::DocumentChange.delete_all
    MosaicRelay::RelaySetting.delete_all
    PageModel.records = []
    BlogModel.records = []
    AnnouncementModel.records = []
    MosaicRelay.configure do |configuration|
      configuration.page_model = PageModel
      configuration.blog_model = BlogModel
    end
  end

  teardown do
    MosaicRelay.reset_configuration!
    MosaicRelay::SourceRegistry.reset!
    MosaicRelay::RelaySetting.delete_all
  end

  test "walks a paginated snapshot and then switches to ledger events" do
    PageModel.records = [ Record.new(id: 1), Record.new(id: 2) ]
    page_change = MosaicRelay::DocumentChange.create!(
      external_id: "pages:1",
      resource_type: "Page",
      resource_id: 1,
      occurred_at: Time.current
    )

    stub_serializers do
      first_page = MosaicRelay::DocumentFeed.new(cursor: nil, page_size: 1).call
      first_cursor = first_page.fetch("next_cursor")

      assert_equal [ "pages:1" ], first_page.fetch("documents").map { |document| document.fetch("external_id") }
      first_state = MosaicRelay::CursorCodec.decode(first_cursor)
      assert_equal({ "mode" => "snapshot", "phase" => "pages", "last_id" => 1, "high_water" => page_change.id, "v" => 1 }, first_state)

      second_page = MosaicRelay::DocumentFeed.new(cursor: first_cursor, page_size: 1).call
      second_cursor = second_page.fetch("next_cursor")
      assert_equal [ "pages:2" ], second_page.fetch("documents").map { |document| document.fetch("external_id") }
      assert_equal "pages", MosaicRelay::CursorCodec.decode(second_cursor).fetch("phase")

      final_snapshot = MosaicRelay::DocumentFeed.new(cursor: second_cursor, page_size: 1).call
      event_cursor = final_snapshot.fetch("cursor")
      assert_equal [], final_snapshot.fetch("documents")
      assert_equal({ "mode" => "events", "after" => page_change.id, "v" => 1 }, MosaicRelay::CursorCodec.decode(event_cursor))
    end
  end

  test "does not include changes created after the initial snapshot high-water mark until events" do
    PageModel.records = [ Record.new(id: 1) ]

    stub_serializers do
      snapshot = MosaicRelay::DocumentFeed.new(cursor: nil, page_size: 10).call
      event = MosaicRelay::DocumentChange.create!(
        external_id: "pages:1",
        resource_type: "Page",
        resource_id: 1,
        occurred_at: Time.current
      )

      final_cursor = snapshot.fetch("cursor")
      assert_equal 0, MosaicRelay::CursorCodec.decode(final_cursor).fetch("after")

      events = MosaicRelay::DocumentFeed.new(cursor: final_cursor, page_size: 10).call
      assert_equal [ event.id ], events.fetch("documents").map { |document| document.fetch("change_id") }
    end
  end

  test "excludes hidden, draft, and future-scheduled blogs from the snapshot" do
    BlogModel.records = [
      BlogRecord.new(id: 1, visible_value: true, published_at: 1.hour.ago),
      BlogRecord.new(id: 2, visible_value: false, published_at: 1.hour.ago),
      BlogRecord.new(id: 3, visible_value: true, published_at: nil),
      BlogRecord.new(id: 4, visible_value: true, published_at: 1.hour.from_now)
    ]

    stub_serializers do
      response = MosaicRelay::DocumentFeed.new(cursor: nil, page_size: 10).call

      assert_equal [ "blogs:1" ], response.fetch("documents").map { |document| document.fetch("external_id") }
    end
  end

  test "paginates incremental changes and omits next_cursor on the final page" do
    first = MosaicRelay::DocumentChange.create!(external_id: "pages:1", resource_type: "Page", resource_id: 1, occurred_at: Time.current)
    second = MosaicRelay::DocumentChange.create!(external_id: "blogs:2", resource_type: "Blog", resource_id: 2, occurred_at: Time.current)

    stub_serializers do
      first_page = MosaicRelay::DocumentFeed.new(cursor: MosaicRelay::CursorCodec.encode(mode: "events", after: 0), page_size: 1).call
      next_cursor = first_page.fetch("next_cursor")
      assert_equal [ first.id ], first_page.fetch("documents").map { |document| document.fetch("change_id") }

      final_page = MosaicRelay::DocumentFeed.new(cursor: next_cursor, page_size: 1).call
      assert_equal [ second.id ], final_page.fetch("documents").map { |document| document.fetch("change_id") }

      empty_page = MosaicRelay::DocumentFeed.new(cursor: final_page.fetch("next_cursor"), page_size: 1).call
      assert_equal [], empty_page.fetch("documents")
      assert_nil empty_page["next_cursor"]
    end
  end

  test "serializes a registered source with only the selected fields" do
    MosaicRelay.register_source(
      key: "announcements",
      model: AnnouncementModel,
      title: :title,
      fields: %i[summary private_notes],
      field_options: %i[summary private_notes],
      scope: :published,
      collection_path: "/announcements",
      record_path: ->(record) { "/announcements/#{record.id}" }
    )
    AnnouncementModel.records = [
      AnnouncementRecord.new(
        id: 3,
        title: "Road closure",
        summary: "The north entrance is closed.",
        private_notes: "Operations only.",
        updated_at: Time.current
      )
    ]
    MosaicRelay::RelaySetting.current.update!(
      public_base_url: "https://mosaic.example",
      source_types: [ "announcements" ],
      source_field_mappings: { "announcements" => [ "summary" ] }
    )

    response = MosaicRelay::DocumentFeed.new(cursor: nil, page_size: 10).call
    document = response.fetch("documents").sole

    assert_equal "announcements:3", document.fetch("external_id")
    assert_includes document.fetch("content"), "The north entrance is closed."
    refute_includes document.fetch("content"), "Operations only."
  end

  test "returns a tombstone when a custom source record is no longer public" do
    register_announcements_source
    record = AnnouncementRecord.new(id: 3, title: "Road closure", summary: "Closed", updated_at: Time.current, published_value: true)
    AnnouncementModel.records = [ record ]
    MosaicRelay::RelaySetting.current.update!(source_types: [ "announcements" ])
    change = MosaicRelay::DocumentChange.create!(external_id: "announcements:3", resource_type: AnnouncementModel.name, resource_id: 3, occurred_at: Time.current)
    record.published_value = false

    response = MosaicRelay::DocumentFeed.new(cursor: MosaicRelay::CursorCodec.encode(mode: "events", after: change.id - 1)).call

    assert_equal [ { "external_id" => "announcements:3", "deleted" => true } ], response.fetch("documents")
  end

  test "delivers source-disable tombstones even after the source is no longer selected" do
    MosaicRelay::RelaySetting.current.update!(source_types: [])
    change = MosaicRelay::DocumentChange.create!(
      external_id: "announcements:3",
      resource_type: "Announcement",
      resource_id: 3,
      occurred_at: Time.current,
      deleted: true
    )

    response = MosaicRelay::DocumentFeed.new(cursor: MosaicRelay::CursorCodec.encode(mode: "events", after: change.id - 1)).call

    assert_equal [ { "external_id" => "announcements:3", "deleted" => true } ], response.fetch("documents")
  end

  test "rejects invalid feed state values" do
    invalid_cursor = MosaicRelay::CursorCodec.encode(mode: "snapshot", phase: "unknown", last_id: 0, high_water: 0)

    assert_raises MosaicRelay::CursorCodec::InvalidCursor do
      MosaicRelay::DocumentFeed.new(cursor: invalid_cursor).call
    end

    invalid_integer = MosaicRelay::CursorCodec.encode(mode: "events", after: "not-an-integer")
    assert_raises MosaicRelay::CursorCodec::InvalidCursor do
      MosaicRelay::DocumentFeed.new(cursor: invalid_integer).call
    end
  end

  private

  def register_announcements_source
    MosaicRelay.register_source(
      key: "announcements",
      model: AnnouncementModel,
      title: :title,
      fields: %i[summary private_notes],
      field_options: %i[summary private_notes],
      scope: :published,
      collection_path: "/announcements",
      record_path: ->(record) { "/announcements/#{record.id}" }
    )
  end

  def stub_serializers
    original_page = MosaicRelay::DocumentSerializer.method(:for_page)
    original_blog = MosaicRelay::DocumentSerializer.method(:for_blog)
    original_change = MosaicRelay::DocumentSerializer.method(:for_change)

    MosaicRelay::DocumentSerializer.define_singleton_method(:for_page) do |record, **|
      { "external_id" => "pages:#{record.id}" }
    end
    MosaicRelay::DocumentSerializer.define_singleton_method(:for_blog) do |record, **|
      { "external_id" => "blogs:#{record.id}" }
    end
    MosaicRelay::DocumentSerializer.define_singleton_method(:for_change) do |change, **|
      { "external_id" => change.external_id, "change_id" => change.id }
    end

    yield
  ensure
    MosaicRelay::DocumentSerializer.define_singleton_method(:for_page, original_page)
    MosaicRelay::DocumentSerializer.define_singleton_method(:for_blog, original_blog)
    MosaicRelay::DocumentSerializer.define_singleton_method(:for_change, original_change)
  end
end

# frozen_string_literal: true

require "test_helper"

class MosaicRelayModelHooksTest < ActiveSupport::TestCase
  class FakeRecord
    class << self
      attr_reader :commit_callbacks

      def after_commit(method_name, on:)
        @commit_callbacks ||= []
        @commit_callbacks << [ method_name, on ]
      end
    end

    attr_reader :id

    def initialize(id: nil)
      @id = id
    end
  end

  def with_method_stub(receiver, method_name, replacement)
    original_method = receiver.method(method_name)
    receiver.define_singleton_method(method_name, &replacement)
    yield
  ensure
    receiver.define_singleton_method(method_name, original_method)
  end

  setup do
    @previous_page_model = MosaicRelay.configuration.page_model
    @previous_blog_model = MosaicRelay.configuration.blog_model
  end

  teardown do
    MosaicRelay.configure do |config|
      config.page_model = @previous_page_model
      config.blog_model = @previous_blog_model
    end
  end

  test "installs document callbacks on the configured page model" do
    page_model = Class.new(FakeRecord)
    MosaicRelay.configure { |config| config.page_model = page_model }

    MosaicRelay::ModelHooks.install!

    assert_operator page_model, :<, MosaicRelay::TracksPageDocumentChanges
    assert_includes page_model.commit_callbacks,
      [ :record_mosaic_relay_page_document_change, [ :create, :update, :destroy ] ]
  end

  test "does not install duplicate callbacks" do
    page_model = Class.new(FakeRecord)
    MosaicRelay.configure { |config| config.page_model = page_model }

    MosaicRelay::ModelHooks.install!
    first_callback_count = page_model.commit_callbacks.length
    MosaicRelay::ModelHooks.install!

    assert_equal first_callback_count, page_model.commit_callbacks.length
  end

  test "page document callback records the model ID" do
    page_model = Class.new(FakeRecord)
    MosaicRelay.configure { |config| config.page_model = page_model }
    MosaicRelay::ModelHooks.install!
    page = page_model.new(id: 41)
    recorded_ids = []

    with_method_stub(MosaicRelay::ChangeRecorder, :record_page, ->(page_id) { recorded_ids << page_id }) do
      page.send(:record_mosaic_relay_page_document_change)
    end

    assert_equal [ 41 ], recorded_ids
  end

  test "schedules a future blog publication" do
    blog_model = Class.new(FakeRecord) do
      attr_reader :published_at

      def initialize(id: nil, published_at:)
        super(id: id)
        @published_at = published_at
      end

      def scheduled?
        true
      end
    end
    MosaicRelay.configure { |config| config.blog_model = blog_model }
    MosaicRelay::ModelHooks.install!
    blog = blog_model.new(id: 52, published_at: Time.utc(2026, 8, 25, 9))
    scheduled_at = []
    scheduled_job = Struct.new(:blog_id) do
      def perform_later(blog_id)
        self.blog_id = blog_id
      end
    end.new

    stub_class_method(MosaicRelay::ScheduledBlogPublicationJob, :set, lambda { |wait_until:|
      scheduled_at << wait_until
      scheduled_job
    }) do
      blog.send(:schedule_mosaic_relay_blog_publication)
    end

    assert_equal [ blog.published_at ], scheduled_at
    assert_equal blog.id, scheduled_job.blog_id
  end

  test "installs change tracking for dynamically registered sources" do
    model = Class.new(FakeRecord)
    model.define_singleton_method(:name) { "DynamicAnnouncement" }
    model.define_singleton_method(:table_exists?) { true }

    MosaicRelay.register_source(
      key: "announcements",
      model: model,
      fields: %i[summary],
      field_options: %i[summary],
      collection_path: "/announcements",
      record_path: ->(record) { "/announcements/#{record.id}" },
      scope: :all
    )

    MosaicRelay::ModelHooks.install!

    assert_operator model, :<, MosaicRelay::TracksRegisteredSourceChanges
  ensure
    MosaicRelay::SourceRegistry.reset!
  end
end

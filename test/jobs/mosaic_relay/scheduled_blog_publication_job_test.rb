# frozen_string_literal: true

require "test_helper"

class MosaicRelayScheduledBlogPublicationJobTest < ActiveSupport::TestCase
  Blog = Struct.new(:id, :displayable_value, keyword_init: true) do
    def displayable?
      displayable_value
    end
  end

  Model = Class.new do
    class << self
      attr_accessor :records

      def find_by(id:)
        records.find { |record| record.id == id }
      end
    end
  end

  setup do
    @previous_blog_model = MosaicRelay.configuration.blog_model
    MosaicRelay.configure { |configuration| configuration.blog_model = Model }
    Model.records = []
  end

  teardown do
    MosaicRelay.configure { |configuration| configuration.blog_model = @previous_blog_model }
  end

  test "records a blog when the scheduled publication is displayable" do
    blog = Blog.new(id: 7, displayable_value: true)
    Model.records = [ blog ]
    recorded = []

    stub_class_method(MosaicRelay::ChangeRecorder, :record_blog, ->(value) { recorded << value }) do
      MosaicRelay::ScheduledBlogPublicationJob.perform_now(blog.id)
    end

    assert_equal [ blog ], recorded
  end

  test "does not record missing or not-yet-displayable blogs" do
    Model.records = [ Blog.new(id: 8, displayable_value: false) ]
    recorded = []

    stub_class_method(MosaicRelay::ChangeRecorder, :record_blog, ->(value) { recorded << value }) do
      MosaicRelay::ScheduledBlogPublicationJob.perform_now(8)
      MosaicRelay::ScheduledBlogPublicationJob.perform_now(999)
    end

    assert_empty recorded
  end
end

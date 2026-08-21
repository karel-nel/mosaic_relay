# frozen_string_literal: true

module MosaicRelay
  class ScheduledBlogPublicationJob < ApplicationJob
    queue_as :default

    def perform(blog_id)
      blog = blog_model&.find_by(id: blog_id)
      ChangeRecorder.record_blog(blog) if blog&.displayable?
    end

    private

    def blog_model
      MosaicRelay.configuration.blog_model || (defined?(::Blog) ? ::Blog : nil)
    end
  end
end

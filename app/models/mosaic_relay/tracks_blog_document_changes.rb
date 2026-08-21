# frozen_string_literal: true

module MosaicRelay
  module TracksBlogDocumentChanges
    extend ActiveSupport::Concern

    included do
      after_commit :record_mosaic_relay_blog_document_change, on: [ :create, :update, :destroy ]
      after_commit :schedule_mosaic_relay_blog_publication, on: [ :create, :update ]
    end

    private

    def record_mosaic_relay_blog_document_change
      MosaicRelay::ChangeRecorder.record_blog(id)
    end

    def schedule_mosaic_relay_blog_publication
      return unless respond_to?(:scheduled?) && scheduled?
      return unless respond_to?(:published_at) && published_at.present?

      MosaicRelay::ScheduledBlogPublicationJob.set(wait_until: published_at).perform_later(id)
    end
  end
end

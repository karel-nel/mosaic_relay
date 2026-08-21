# frozen_string_literal: true

module MosaicRelay
  module TracksBlogAssociationChanges
    extend ActiveSupport::Concern

    included do
      after_commit :record_mosaic_relay_blog_association_change, on: [ :create, :update, :destroy ]
    end

    private

    def record_mosaic_relay_blog_association_change
      MosaicRelay::ChangeRecorder.record_blog(blog_id)
    end
  end
end

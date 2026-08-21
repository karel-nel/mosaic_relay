# frozen_string_literal: true

module MosaicRelay
  module TracksPodChanges
    extend ActiveSupport::Concern

    included do
      before_destroy :capture_mosaic_relay_pod_page_ids
      after_commit :record_mosaic_relay_pod_page_changes, on: [ :create, :update, :destroy ]
    end

    private

    def capture_mosaic_relay_pod_page_ids
      @mosaic_relay_pod_page_ids = MosaicRelay::PageChangeTracker.page_ids_for_pod(self)
    end

    def record_mosaic_relay_pod_page_changes
      if destroyed?
        Array(@mosaic_relay_pod_page_ids).each { |page_id| MosaicRelay::PageChangeTracker.record_page(page_id) }
      else
        MosaicRelay::PageChangeTracker.record_for_pod(self)
      end
    end
  end
end

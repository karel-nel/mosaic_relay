# frozen_string_literal: true

module MosaicRelay
  module TracksAssociatedPageChanges
    extend ActiveSupport::Concern

    included do
      before_destroy :capture_mosaic_relay_page_id
      after_commit :record_mosaic_relay_associated_page_change, on: [ :create, :update, :destroy ]
    end

    private

    def capture_mosaic_relay_page_id
      @mosaic_relay_page_id = associated_mosaic_relay_page_id
    end

    def record_mosaic_relay_associated_page_change
      MosaicRelay::PageChangeTracker.record_page(@mosaic_relay_page_id || associated_mosaic_relay_page_id)
    end

    def associated_mosaic_relay_page_id
      return page_id if respond_to?(:page_id)
      return page_composition&.page_id if respond_to?(:page_composition)
      return page_section&.page_composition&.page_id if respond_to?(:page_section)
      return page_section_slot&.page_section&.page_composition&.page_id if respond_to?(:page_section_slot)

      nil
    end
  end
end

# frozen_string_literal: true

module MosaicRelay
  module TracksPageDocumentChanges
    extend ActiveSupport::Concern

    included do
      after_commit :record_mosaic_relay_page_document_change, on: [ :create, :update, :destroy ]
    end

    private

    def record_mosaic_relay_page_document_change
      MosaicRelay::ChangeRecorder.record_page(id)
    end
  end
end

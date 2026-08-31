# frozen_string_literal: true

module MosaicRelay
  module TracksRegisteredSourceChanges
    extend ActiveSupport::Concern

    included do
      after_commit :record_mosaic_relay_registered_source_change, on: %i[create update destroy]
    end

    private

    def record_mosaic_relay_registered_source_change
      source_key = MosaicRelay::SourceRegistry.source_type_for(self.class)
      return unless source_key

      MosaicRelay::ChangeRecorder.record(
        external_id: MosaicRelay::MigrationContract.external_id(source_key, id),
        resource_type: self.class.name,
        resource_id: id,
        occurred_at: Time.current,
        deleted: destroyed?
      )
    end
  end
end

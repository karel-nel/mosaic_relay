class AddSourceSelectionToMosaicRelaySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :mosaic_relay_settings, :source_types, :text unless column_exists?(:mosaic_relay_settings, :source_types)
    add_column :mosaic_relay_settings, :source_field_mappings, :text unless column_exists?(:mosaic_relay_settings, :source_field_mappings)
  end
end

class AddDeletedToMosaicRelayDocumentChanges < ActiveRecord::Migration[7.1]
  def change
    add_column :mosaic_relay_document_changes, :deleted, :boolean, null: false, default: false unless column_exists?(:mosaic_relay_document_changes, :deleted)
  end
end

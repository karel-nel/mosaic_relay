class CreateMosaicRelayDocumentChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :mosaic_relay_document_changes do |t|
      t.string :external_id, null: false
      t.string :resource_type, null: false
      t.bigint :resource_id
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :mosaic_relay_document_changes, :external_id
    add_index :mosaic_relay_document_changes, [ :resource_type, :resource_id ]
    add_index :mosaic_relay_document_changes, [ :occurred_at, :id ]
  end
end

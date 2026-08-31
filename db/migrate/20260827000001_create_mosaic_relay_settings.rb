class CreateMosaicRelaySettings < ActiveRecord::Migration[7.1]
  def change
    create_table :mosaic_relay_settings do |t|
      t.string :source_token
      t.string :public_base_url
      t.string :default_language, null: false, default: "en"
      t.integer :page_size, null: false, default: 25
      t.text :widget_markup

      t.timestamps
    end
  end
end

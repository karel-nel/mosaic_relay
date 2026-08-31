# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_08_31_000002) do
  create_table "mosaic_relay_document_changes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "deleted", default: false, null: false
    t.string "external_id", null: false
    t.datetime "occurred_at", null: false
    t.bigint "resource_id"
    t.string "resource_type", null: false
    t.datetime "updated_at", null: false
    t.index [ "external_id" ], name: "index_mosaic_relay_document_changes_on_external_id"
    t.index [ "occurred_at", "id" ], name: "index_mosaic_relay_document_changes_on_occurred_at_and_id"
    t.index [ "resource_type", "resource_id" ], name: "idx_on_resource_type_resource_id_3ab9bd06f4"
  end

  create_table "mosaic_relay_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_language", default: "en", null: false
    t.integer "page_size", default: 25, null: false
    t.string "public_base_url"
    t.text "source_field_mappings"
    t.string "source_token"
    t.text "source_types"
    t.datetime "updated_at", null: false
    t.text "widget_markup"
  end
end

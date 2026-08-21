# frozen_string_literal: true

require "test_helper"

class MosaicRelayDocumentChangeTest < ActiveSupport::TestCase
  test "uses the engine-owned table" do
    assert_equal "mosaic_relay_document_changes", MosaicRelay::DocumentChange.table_name
  end

  test "requires the fields used by the document feed" do
    change = MosaicRelay::DocumentChange.new

    assert_not change.valid?
    assert_includes change.errors.attribute_names, :external_id
    assert_includes change.errors.attribute_names, :resource_type
    assert_includes change.errors.attribute_names, :occurred_at
  end

  test "defines sequence scopes for incremental feeds" do
    after_sequence = MosaicRelay::DocumentChange.after_sequence(12)

    assert_kind_of ActiveRecord::Relation, after_sequence
    assert_includes after_sequence.to_sql, "id"
    assert_includes after_sequence.to_sql, ">"
    assert_includes MosaicRelay::DocumentChange.ordered.to_sql, "ORDER BY"
  end
end

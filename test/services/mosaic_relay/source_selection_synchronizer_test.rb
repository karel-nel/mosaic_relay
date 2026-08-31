# frozen_string_literal: true

require "test_helper"

class MosaicRelaySourceSelectionSynchronizerTest < ActiveSupport::TestCase
  Setting = Struct.new(:source_types, :source_field_mappings)

  test "tombstones disabled sources and reindexes enabled or changed sources" do
    tombstones = []
    documents = []
    setting = Setting.new([ "blogs", "announcements" ], { "blogs" => [ "excerpt" ], "announcements" => [ "summary" ] })

    stub_class_method(MosaicRelay::ChangeRecorder, :record_source_tombstones, ->(source_key) { tombstones << source_key }) do
      stub_class_method(MosaicRelay::ChangeRecorder, :record_source_documents, ->(source_key) { documents << source_key }) do
        MosaicRelay::SourceSelectionSynchronizer.call(
          previous_source_types: [ "pages", "blogs" ],
          previous_field_mappings: { "pages" => [ "content" ], "blogs" => [ "content" ] },
          relay_setting: setting
        )
      end
    end

    assert_equal [ "pages" ], tombstones
    assert_equal [ "announcements", "blogs" ], documents
  end
end

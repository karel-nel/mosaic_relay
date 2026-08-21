# frozen_string_literal: true

require "test_helper"

class MosaicRelayChangeRecorderTest < ActiveSupport::TestCase
  Resource = Struct.new(:id)

  test "records pages using the canonical external id" do
    calls = []
    timestamp = Time.utc(2026, 8, 21, 10, 15)

    stub_class_method(MosaicRelay::DocumentChange, :create!, ->(attributes) { calls << attributes; attributes }) do
      result = MosaicRelay::ChangeRecorder.record_page(Resource.new(42), occurred_at: timestamp)

      assert_equal calls.first, result
    end

    assert_equal [ {
      external_id: "pages:42",
      resource_type: "Page",
      resource_id: 42,
      occurred_at: timestamp
    } ], calls
  end

  test "records blogs from either a model-like object or an id" do
    calls = []

    stub_class_method(MosaicRelay::DocumentChange, :create!, ->(attributes) { calls << attributes; attributes }) do
      MosaicRelay::ChangeRecorder.record_blog(7, occurred_at: Time.utc(2026, 8, 21))
    end

    assert_equal "blogs:7", calls.first.fetch(:external_id)
    assert_equal "Blog", calls.first.fetch(:resource_type)
    assert_equal 7, calls.first.fetch(:resource_id)
  end

  test "does not create a change for a missing resource id" do
    called = false

    stub_class_method(MosaicRelay::DocumentChange, :create!, ->(*) { called = true }) do
      assert_nil MosaicRelay::ChangeRecorder.record_page(nil)
    end

    assert_not called
  end

  test "supports recording a custom resource" do
    calls = []
    timestamp = Time.utc(2026, 8, 21, 10, 15)

    stub_class_method(MosaicRelay::DocumentChange, :create!, ->(attributes) { calls << attributes; attributes }) do
      MosaicRelay::ChangeRecorder.record(
        external_id: "pages:42",
        resource_type: "Page",
        resource_id: 42,
        occurred_at: timestamp
      )
    end

    assert_equal timestamp, calls.first.fetch(:occurred_at)
  end

  test "appends changes that can be read by sequence" do
    MosaicRelay::DocumentChange.delete_all
    first = MosaicRelay::ChangeRecorder.record_page(11, occurred_at: Time.utc(2026, 8, 21, 10, 15))
    second = MosaicRelay::ChangeRecorder.record_blog(22, occurred_at: Time.utc(2026, 8, 21, 10, 16))

    assert_equal [ second ], MosaicRelay::DocumentChange.after_sequence(first.id).ordered.to_a
    assert_equal "blogs:22", second.external_id
  end
end

# frozen_string_literal: true

require "test_helper"

class MosaicRelayPageChangeTrackerTest < ActiveSupport::TestCase
  def with_method_stub(receiver, method_name, replacement)
    original_method = receiver.method(method_name)
    receiver.define_singleton_method(method_name, &replacement)
    yield
  ensure
    receiver.define_singleton_method(method_name, original_method)
  end

  test "records each unique page associated with a pod" do
    page_pods = Class.new do
      def pluck(*)
        [ 11, 12 ]
      end
    end.new

    page_element_model = Class.new do
      class << self
        def joins(*)
          self
        end

        def where(*)
          self
        end

        def pluck(*)
          [ 12, 13 ]
        end
      end
    end

    MosaicRelay.configure do |config|
      config.page_element_model = page_element_model
    end

    pod = Struct.new(:id, :page_pods).new(7, page_pods)

    assert_equal [ 11, 12, 13 ], MosaicRelay::PageChangeTracker.page_ids_for_pod(pod)
  end

  test "records page changes for a pod without duplicates" do
    recorded_ids = []
    pod = Object.new

    with_method_stub(MosaicRelay::ChangeRecorder, :record_page, ->(page_id) { recorded_ids << page_id }) do
      with_method_stub(MosaicRelay::PageChangeTracker, :page_ids_for_pod, ->(*) { [ 21, 22, 21 ] }) do
        MosaicRelay::PageChangeTracker.record_for_pod(pod)
      end
    end

    assert_equal [ 21, 22 ], recorded_ids
  end

  test "ignores blank page IDs" do
    recorded_ids = []

    with_method_stub(MosaicRelay::ChangeRecorder, :record_page, ->(page_id) { recorded_ids << page_id }) do
      MosaicRelay::PageChangeTracker.record_page(nil)
      MosaicRelay::PageChangeTracker.record_page(31)
    end

    assert_equal [ 31 ], recorded_ids
  end
end

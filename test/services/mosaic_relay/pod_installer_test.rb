# frozen_string_literal: true

require "test_helper"

class MosaicRelayPodInstallerTest < ActiveSupport::TestCase
  FakeRecord = Struct.new(
    :pod_type, :name, :description, :category, :icon, :schema, :metadata, :active,
    keyword_init: true
  ) do
    attr_reader :saved

    def assign_attributes(attributes)
      attributes.each { |name, value| public_send("#{name}=", value) }
    end

    def save!
      @saved = true
    end
  end

  test "installs the canonical Relay widget Pod definition" do
    record = FakeRecord.new(pod_type: "relay_chat")
    model = Object.new
    model.define_singleton_method(:find_or_initialize_by) do |pod_type:|
      raise "unexpected pod type" unless pod_type == "relay_chat"

      record
    end

    result = MosaicRelay::PodInstaller.call(model:)

    assert_equal :installed, result.status
    assert_same record, result.record
    assert_equal "Relay Chat", record.name
    assert_equal({}, record.schema)
    assert record.saved
  end

  test "uses YAML only when the host has no PodDefinition model" do
    result = MosaicRelay::PodInstaller.call(model: nil)

    assert_equal :yaml_only, result.status
    assert_nil result.record
  end
end

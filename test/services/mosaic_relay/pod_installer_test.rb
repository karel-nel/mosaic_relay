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

  test "installs the bundled definition through the host PodDefinition model" do
    record = FakeRecord.new(pod_type: "llm_chat_window")
    model = Object.new
    model.define_singleton_method(:find_or_initialize_by) do |pod_type:|
      raise "unexpected pod type" unless pod_type == "llm_chat_window"

      record
    end

    result = MosaicRelay::PodInstaller.call(model:)

    assert_equal :installed, result.status
    assert_same record, result.record
    assert_equal "LLM Chat Window", record.name
    assert_equal "content", record.category
    assert_equal true, record.active
    assert_equal true, record.metadata.fetch("usable_in_sections")
    assert_equal [ "content", "tabs" ], record.metadata.fetch("recommended_for")
    assert record.saved
  end

  test "uses YAML only when the host has no PodDefinition model" do
    result = MosaicRelay::PodInstaller.call(model: nil)

    assert_equal :yaml_only, result.status
    assert_nil result.record
    assert_includes result.message, "config/pod_definitions.yml"
  end
end

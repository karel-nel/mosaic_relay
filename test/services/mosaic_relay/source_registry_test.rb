# frozen_string_literal: true

require "test_helper"

class MosaicRelaySourceRegistryTest < ActiveSupport::TestCase
  Record = Struct.new(:id)

  Model = Class.new do
    def self.all
      [ Record.new(17) ]
    end

    def self.table_exists?
      true
    end
  end

  setup do
    MosaicRelay::SourceRegistry.reset!
  end

  teardown do
    MosaicRelay::SourceRegistry.reset!
  end

  test "makes a source selectable only when its public endpoint renders" do
    MosaicRelay.register_source(
      key: "announcements",
      model: Model,
      fields: %i[summary body],
      field_options: %i[summary body],
      collection_path: "/announcements",
      record_path: ->(record) { "/announcements/#{record.id}" },
      scope: :all
    )
    endpoint = MosaicRelay::PublicEndpointValidator::Result.new(available: true, path: "/announcements")
    paths = []

    stub_class_method(MosaicRelay::PublicEndpointValidator, :call, ->(path:, **) { paths << path; endpoint }) do
      status = MosaicRelay::SourceRegistry.source_status(MosaicRelay::SourceRegistry.fetch("announcements"), host: "cms.example")

      assert status.ingestible?
      assert_equal "/announcements", status.endpoint.path
      assert_equal [ "announcements" ], MosaicRelay::SourceRegistry.options.map(&:key)
    end

    assert_equal [ "/announcements", "/announcements/17", "/announcements", "/announcements/17" ], paths
  end

  test "reports an endpoint failure and rejects fields outside the source contract" do
    MosaicRelay.register_source(
      key: "announcements",
      model: Model,
      fields: %i[summary],
      field_options: %i[summary body],
      collection_path: "/announcements",
      record_path: ->(record) { "/announcements/#{record.id}" },
      scope: :all
    )
    endpoint = MosaicRelay::PublicEndpointValidator::Result.new(available: false, reason: "returns HTTP 404", path: "/announcements")

    stub_class_method(MosaicRelay::PublicEndpointValidator, :call, ->(**) { endpoint }) do
      status = MosaicRelay::SourceRegistry.source_status(MosaicRelay::SourceRegistry.fetch("announcements"))

      refute status.ingestible?
      assert_equal "returns HTTP 404", status.reason
    end

    assert_equal({ "announcements" => [ "body", "summary" ] },
                 MosaicRelay::SourceRegistry.normalize_field_mappings("announcements" => [ "body", "secret", "summary", "body" ]))
  end

  test "rejects a source that is missing its public record contract" do
    MosaicRelay.register_source(
      key: "announcements",
      model: Model,
      fields: %i[summary],
      collection_path: "/announcements",
      scope: :all
    )

    status = MosaicRelay::SourceRegistry.source_status(MosaicRelay::SourceRegistry.fetch("announcements"))

    refute status.ingestible?
    assert_equal "does not declare a public record URL", status.reason
  end

  test "rejects a source when its representative public record does not render" do
    MosaicRelay.register_source(
      key: "announcements",
      model: Model,
      fields: %i[summary],
      collection_path: "/announcements",
      record_path: ->(record) { "/announcements/#{record.id}" },
      scope: :all
    )
    responses = [
      MosaicRelay::PublicEndpointValidator::Result.new(available: true, path: "/announcements"),
      MosaicRelay::PublicEndpointValidator::Result.new(available: false, reason: "returns HTTP 404", path: "/announcements/17")
    ]

    stub_class_method(MosaicRelay::PublicEndpointValidator, :call, ->(**) { responses.shift }) do
      status = MosaicRelay::SourceRegistry.source_status(MosaicRelay::SourceRegistry.fetch("announcements"))

      refute status.ingestible?
      assert_equal "returns HTTP 404", status.reason
    end
  end

  test "does not allow a custom source to replace a stable built-in identity" do
    assert_raises(ArgumentError) do
      MosaicRelay.register_source(key: "pages", model: Model)
    end
  end

  test "loads host-provided sources dynamically on each registry lookup" do
    MosaicRelay.configure do |configuration|
      configuration.source_provider = -> {
        [ {
          key: "announcements",
          model: Model,
          fields: %i[summary body],
          field_options: %i[summary body],
          collection_path: "/announcements",
          record_path: ->(record) { "/announcements/#{record.id}" },
          scope: :all
        } ]
      }
    end

    assert_equal [ "announcements" ], MosaicRelay::SourceRegistry.keys.sort
    assert_equal "announcements", MosaicRelay::SourceRegistry.fetch("announcements").key
  ensure
    MosaicRelay.reset_configuration!
  end

  test "accepts a dynamically provided Source contract" do
    source = MosaicRelay::SourceRegistry::Source.new(key: "announcements", model_name: Model.name)

    MosaicRelay.configure do |configuration|
      configuration.source_provider = -> { [ source ] }
    end

    assert_same source, MosaicRelay::SourceRegistry.fetch("announcements")
  ensure
    MosaicRelay.reset_configuration!
  end
end

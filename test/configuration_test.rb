require "test_helper"

class MosaicRelayConfigurationTest < ActiveSupport::TestCase
  setup do
    MosaicRelay.reset_configuration!
    MosaicRelay::RelaySetting.delete_all
  end

  teardown do
    MosaicRelay.reset_configuration!
    MosaicRelay::RelaySetting.delete_all
  end

  test "loads document-feed configuration from the Relay Settings record" do
    MosaicRelay::RelaySetting.current.update!(
      source_token: "source-token",
      public_base_url: "https://mosaic.example/",
      default_language: "en-ZA",
      page_size: 50
    )
    configuration = MosaicRelay.configuration

    assert_equal "source-token", configuration.source_token
    assert_equal "https://mosaic.example", configuration.public_base_url
    assert_equal "en-ZA", configuration.default_language
    assert_equal 50, configuration.page_size
  end

  test "keeps Mosaic adapter configuration separate from Relay settings" do
    MosaicRelay::RelaySetting.current.update!(
      source_token: "source-token",
      public_base_url: "https://relay-settings.example/",
      widget_markup: "<niimble-relay-chat></niimble-relay-chat>",
      page_size: 250
    )

    MosaicRelay.configure do |configuration|
      configuration.page_model = Class.new
    end

    assert_equal "https://relay-settings.example", MosaicRelay.configuration.public_base_url
    assert_equal "<niimble-relay-chat></niimble-relay-chat>", MosaicRelay.configuration.widget_markup
    assert_equal 250, MosaicRelay.configuration.page_size
    assert MosaicRelay.configuration.page_model
  end

  test "does not provide environment configuration" do
    refute_respond_to MosaicRelay, :configure_from_env!
  end

  test "uses safe defaults for invalid page sizes" do
    configuration = MosaicRelay::Configuration.new(page_size: "invalid")

    assert_equal 25, configuration.page_size
  end

  test "preserves an explicit empty source selection" do
    configuration = MosaicRelay::Configuration.new(source_types: [])

    assert_equal [], configuration.source_types
  end
end

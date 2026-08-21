require "test_helper"

class MosaicRelayConfigurationTest < ActiveSupport::TestCase
  setup do
    MosaicRelay.reset_configuration!
  end

  teardown do
    MosaicRelay.reset_configuration!
  end

  test "loads Relay configuration from environment variables" do
    env = {
      "RELAY_SOURCE_TOKEN" => "source-token",
      "RELAY_PUBLIC_BASE_URL" => "https://mosaic.example/",
      "RELAY_CHAT_BASE_URL" => "https://relay.example/",
      "RELAY_CHAT_TOKEN" => "chat-token",
      "RELAY_CHAT_TENANT_KEY" => "mosaic-site",
      "RELAY_CHAT_OPEN_TIMEOUT_SECONDS" => "8",
      "RELAY_CHAT_READ_TIMEOUT_SECONDS" => "60",
      "RELAY_DEFAULT_LANGUAGE" => "en-ZA",
      "RELAY_DOCUMENTS_PAGE_SIZE" => "50"
    }

    configuration = MosaicRelay.configure_from_env!(env)

    assert_equal "source-token", configuration.source_token
    assert_equal "https://mosaic.example", configuration.public_base_url
    assert_equal "https://relay.example", configuration.chat_base_url
    assert_equal "chat-token", configuration.chat_token
    assert_equal "mosaic-site", configuration.chat_tenant_key
    assert_equal 8, configuration.chat_open_timeout_seconds
    assert_equal 60, configuration.chat_read_timeout_seconds
    assert_equal "en-ZA", configuration.default_language
    assert_equal 50, configuration.page_size
  end

  test "supports explicit configuration overrides" do
    MosaicRelay.configure do |configuration|
      configuration.chat_base_url = "https://override.example/"
      configuration.page_size = 500
    end

    assert_equal "https://override.example", MosaicRelay.configuration.chat_base_url
    assert_equal 250, MosaicRelay.configuration.page_size
  end

  test "uses a generic Mosaic tenant key by default" do
    configuration = MosaicRelay::Configuration.from_env({})

    assert_equal "mosaic", configuration.chat_tenant_key
  end

  test "supports explicit Redis and Action Cable dependencies" do
    redis = Object.new
    broadcaster = Object.new

    MosaicRelay.configure do |config|
      config.redis = redis
      config.broadcaster = broadcaster
    end

    assert_same redis, MosaicRelay.configuration.redis
    assert_same broadcaster, MosaicRelay.configuration.broadcaster
  end

  test "uses safe defaults for invalid numeric configuration" do
    configuration = MosaicRelay::Configuration.new(
      chat_open_timeout_seconds: "invalid",
      chat_read_timeout_seconds: 999,
      page_size: 0
    )

    assert_equal 5, configuration.chat_open_timeout_seconds
    assert_equal 120, configuration.chat_read_timeout_seconds
    assert_equal 1, configuration.page_size
  end
end

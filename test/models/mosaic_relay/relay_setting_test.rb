# frozen_string_literal: true

require "test_helper"

class MosaicRelayRelaySettingTest < ActiveSupport::TestCase
  setup do
    MosaicRelay::RelaySetting.delete_all
  end

  teardown do
    MosaicRelay::RelaySetting.delete_all
  end

  test "creates and reuses the singleton settings record" do
    setting = MosaicRelay::RelaySetting.current

    assert setting.persisted?
    assert_equal "en", setting.default_language
    assert_equal 25, setting.page_size
    assert_equal setting.id, MosaicRelay::RelaySetting.current.id
  end

  test "validates document-feed settings" do
    setting = MosaicRelay::RelaySetting.current
    setting.page_size = 251

    refute setting.valid?
    assert_includes setting.errors[:page_size], "must be less than or equal to 250"
  end

  test "accepts an absolute public site URL" do
    setting = MosaicRelay::RelaySetting.current
    setting.public_base_url = "https://www.mosaic.example/"

    assert setting.valid?
  end

  test "rejects a relative or non-http public site URL" do
    setting = MosaicRelay::RelaySetting.current

    [ "/", "www.mosaic.example", "ftp://mosaic.example" ].each do |url|
      setting.public_base_url = url

      refute setting.valid?, url
      assert_includes setting.errors[:public_base_url], "must be an absolute HTTP(S) URL"
    end
  end
end

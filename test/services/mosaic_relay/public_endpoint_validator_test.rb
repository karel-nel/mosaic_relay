# frozen_string_literal: true

require "test_helper"

class MosaicRelayPublicEndpointValidatorTest < ActiveSupport::TestCase
  test "rejects external and admin URLs before issuing a request" do
    external = MosaicRelay::PublicEndpointValidator.call(path: "https://other.example/articles")
    admin = MosaicRelay::PublicEndpointValidator.call(path: "/admin/pages")

    assert_equal false, external.available?
    assert_equal "does not have a public frontend URL", external.reason
    assert_equal false, admin.available?
    assert_equal "does not have a public frontend URL", admin.reason
  end
end

# frozen_string_literal: true

require "test_helper"

class MosaicRelayPlainTextTest < ActiveSupport::TestCase
  test "removes non-searchable HTML and preserves meaningful boundaries" do
    value = <<~HTML
      <div>First&nbsp;line<br>continued</div>
      <script>alert("ignore")</script>
      <p>Second <strong>paragraph</strong>.</p>
    HTML

    assert_equal "First line\ncontinued\n\nSecond paragraph.", MosaicRelay::PlainText.clean(value)
  end

  test "returns an empty string for blank values" do
    assert_equal "", MosaicRelay::PlainText.clean(nil)
    assert_equal "", MosaicRelay::PlainText.clean("   ")
  end
end

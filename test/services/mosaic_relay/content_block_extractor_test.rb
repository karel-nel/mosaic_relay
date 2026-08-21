# frozen_string_literal: true

require "test_helper"

class MosaicRelayContentBlockExtractorTest < ActiveSupport::TestCase
  test "extracts ordered semantic blocks from rich HTML" do
    html = <<~HTML
      <h2>Registration</h2>
      <p>Arrive early.</p>
      <ul><li>Bring identification</li><li>Carry water</li></ul>
      <table><tr><th>Point</th><th>Time</th></tr><tr><td>Start</td><td>05:30</td></tr></table>
      <pre>race --check-in</pre>
    HTML

    assert_equal [
      { "kind" => "heading", "level" => 2, "text" => "Registration" },
      { "kind" => "paragraph", "text" => "Arrive early." },
      { "kind" => "list", "items" => [ "Bring identification", "Carry water" ] },
      { "kind" => "table", "text" => "Point | Time\nStart | 05:30" },
      { "kind" => "code", "text" => "race --check-in" }
    ], MosaicRelay::ContentBlockExtractor.from_html(html)
  end

  test "falls back to a paragraph for unstructured text" do
    assert_equal [ { "kind" => "paragraph", "text" => "Plain content" } ],
                 MosaicRelay::ContentBlockExtractor.from_html("Plain content")
  end
end

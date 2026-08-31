# frozen_string_literal: true

require "test_helper"

class MosaicRelayPodTextExtractorTest < ActiveSupport::TestCase
  SCHEMA = {
    "questions" => {
      "type" => "array",
      "label" => "Questions",
      "position" => 10,
      "item_schema" => {
        "question" => { "type" => "text", "label" => "Question", "position" => 10 },
        "answer" => { "type" => "rich_text", "label" => "Answer", "position" => 20 },
        "url" => { "type" => "url", "label" => "URL", "position" => 30 }
      }
    }
  }.freeze

  setup do
    @extractor = MosaicRelay::PodTextExtractor.new(schema_resolver: ->(_pod_type) { SCHEMA })
  end

  test "keeps semantic fields and excludes presentational URLs" do
    text = @extractor.call(
      pod_type: "relay_faq",
      definition: {
        "questions" => [
          { "question" => "When does registration open?", "answer" => "<p>At <strong>08:00</strong>.</p>", "url" => "https://example.com/cta" }
        ]
      }
    )

    assert_includes text, "Question: When does registration open?"
    assert_includes text, "Answer: At 08:00."
    assert_not_includes text, "https://example.com/cta"
    assert_not_includes text, "<strong>"
  end

  test "extracts rich text and scalar values as ordered blocks" do
    blocks = @extractor.content_blocks(
      pod_type: "relay_faq",
      definition: {
        "questions" => [
          { "question" => "When?", "answer" => "<h3>At 08:00</h3>" }
        ]
      }
    )

    assert_equal [
      { "kind" => "paragraph", "text" => "Question: When?" },
      { "kind" => "heading", "level" => 3, "text" => "At 08:00" }
    ], blocks
  end

  test "does not index known presentational pod types" do
    assert_equal "", @extractor.call(pod_type: "image_widget", definition: { "alt" => "Decorative" })
    assert_equal [], @extractor.content_blocks(pod_type: "image_widget", definition: { "alt" => "Decorative" })
  end

  test "falls back to legacy Mosaic schema lookup signatures" do
    legacy_schemas = Class.new do
      def self.schema_for(type)
        raise "unexpected type" unless type == "legacy"

        { "schema" => { "body" => { "type" => "text" } } }
      end
    end

    admin_was_defined = Object.const_defined?(:Admin, false)
    Object.const_set(:Admin, Module.new) unless admin_was_defined
    Admin.const_set(:PodSchemas, legacy_schemas)
    extractor = MosaicRelay::PodTextExtractor.new

    assert_equal "Body: hello", extractor.call(pod_type: "legacy", definition: { "body" => "hello" })
  ensure
    Admin.send(:remove_const, :PodSchemas) if defined?(Admin) && Admin.const_defined?(:PodSchemas, false)
    Object.send(:remove_const, :Admin) unless admin_was_defined
  end
end

# frozen_string_literal: true

require "test_helper"

class MosaicRelayPageContentExtractorTest < ActiveSupport::TestCase
  Collection = Class.new(Array) do
    def visible
      self
    end

    def includes(*)
      self
    end

    def ordered_by_position
      sort_by(&:position)
    end

    def order(*)
      sort_by(&:position)
    end

    def find_by(state:)
      find { |record| record.state == state }
    end
  end

  Pod = Struct.new(:id, :pod_type, :definition, :updated_at)
  PagePod = Struct.new(:pod, :live_definition, :position, :updated_at)
  Contract = Struct.new(:key)
  Element = Struct.new(:id, :element_contract, :content, :settings, :position, :updated_at, :pod)
  Slot = Struct.new(:page_elements, :position, :updated_at)
  Section = Struct.new(:page_section_slots, :position, :updated_at)
  Composition = Struct.new(:state, :page_sections, :updated_at)
  Page = Struct.new(:title, :meta_description, :updated_at, :page_pods, :sections_value, :page_compositions) do
    def sections?
      sections_value
    end
  end

  test "extracts legacy Pod content and tracks timestamps and types" do
    pod_updated_at = Time.utc(2026, 8, 21, 10, 5)
    page_pod_updated_at = Time.utc(2026, 8, 21, 10, 6)
    schema = {
      "content" => { "type" => "rich_text", "position" => 1, "label" => "Content" }
    }
    pod = Pod.new(7, "basic_text", { "content" => "<p>Registration opens at <strong>08:00</strong>.</p>" }, pod_updated_at)
    page_pod = PagePod.new(pod, pod.definition, 1, page_pod_updated_at)
    page = Page.new(
      "Race information",
      "Everything runners need",
      Time.utc(2026, 8, 21, 10),
      Collection.new([ page_pod ]),
      false,
      Collection.new
    )

    result = MosaicRelay::PageContentExtractor.new(
      page,
      pod_schema_resolver: ->(_pod_type) { schema }
    ).call

    assert_includes result.content, "Title: Race information"
    assert_includes result.content, "Description: Everything runners need"
    assert_includes result.content, "Registration opens at 08:00."
    assert_equal [ { "kind" => "paragraph", "text" => "Registration opens at 08:00." } ], result.content_blocks
    assert_equal [ "basic_text" ], result.pod_types
    assert_equal 1, result.component_count
    assert_equal page_pod_updated_at, result.updated_at
  end

  test "extracts ordered section-builder headings and text" do
    heading = Element.new(1, Contract.new("heading"), { "text" => "Welcome" }, { "level" => "h3" }, 1, Time.utc(2026, 8, 21, 10, 2), nil)
    text = Element.new(2, Contract.new("text"), { "body" => "<p>Read the <em>latest</em> updates.</p>" }, {}, 2, Time.utc(2026, 8, 21, 10, 3), nil)
    slot = Slot.new([ text, heading ], 1, Time.utc(2026, 8, 21, 10, 4))
    section = Section.new([ slot ], 1, Time.utc(2026, 8, 21, 10, 5))
    composition = Composition.new("published", Collection.new([ section ]), Time.utc(2026, 8, 21, 10, 6))
    page = Page.new(
      "Home",
      nil,
      Time.utc(2026, 8, 21, 10),
      Collection.new,
      true,
      Collection.new([ composition ])
    )

    result = MosaicRelay::PageContentExtractor.new(page).call

    assert_equal [
      { "kind" => "heading", "level" => 3, "text" => "Welcome" },
      { "kind" => "paragraph", "text" => "Read the latest updates." }
    ], result.content_blocks
    assert_equal "Title: Home\n\nWelcome\n\nRead the latest updates.", result.content
    assert_equal 2, result.component_count
  end
end

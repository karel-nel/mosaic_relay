# frozen_string_literal: true

require "nokogiri"

module MosaicRelay
  class ContentBlockExtractor
    SELECTOR = "h1, h2, h3, h4, h5, h6, p, ul, ol, table, pre".freeze

    class << self
      def from_html(value)
        return [] if value.blank?

        fragment = Nokogiri::HTML5.fragment(value.to_s)
        fragment.css("script, style, template, noscript").remove
        blocks = fragment.css(SELECTOR).filter_map { |node| block_for(node) }
        return blocks if blocks.present?

        from_text(fragment.text)
      rescue Nokogiri::XML::SyntaxError
        from_text(value)
      end

      def from_text(value)
        PlainText.clean(value).split(/\n{2,}/).filter_map do |paragraph|
          text = PlainText.clean(paragraph)
          { "kind" => "paragraph", "text" => text } if text.present?
        end
      end

      private

      def block_for(node)
        case node.name
        when /\Ah([1-6])\z/
          text_block("heading", node, "level" => Regexp.last_match(1).to_i)
        when "p"
          text_block("paragraph", node)
        when "ul", "ol"
          items = node.element_children.filter_map do |item|
            PlainText.clean(item.to_html).presence if item.name == "li"
          end
          { "kind" => "list", "items" => items } if items.present?
        when "table"
          text = table_text(node)
          { "kind" => "table", "text" => text } if text.present?
        when "pre"
          text_block("code", node)
        end
      end

      def text_block(kind, node, extra = {})
        text = PlainText.clean(node.to_html)
        return if text.blank?

        { "kind" => kind, "text" => text }.merge(extra)
      end

      def table_text(node)
        node.css("tr").filter_map do |row|
          cells = row.css("th, td").filter_map { |cell| PlainText.clean(cell.to_html).presence }
          cells.join(" | ") if cells.present?
        end.join("\n")
      end
    end
  end
end

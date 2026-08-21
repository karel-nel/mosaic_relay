# frozen_string_literal: true

require "nokogiri"

module MosaicRelay
  module PlainText
    BLOCK_TAGS = %w[address article aside blockquote div dl dt dd fieldset figcaption figure footer h1 h2 h3 h4 h5 h6 header li main ol p pre section table td th tr ul].freeze
    REMOVED_TAGS = %w[canvas iframe noscript script style svg template].freeze

    module_function

    def clean(value)
      return "" if value.blank?

      fragment = Nokogiri::HTML5.fragment(value.to_s)
      fragment.css(REMOVED_TAGS.join(",")).remove
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css(BLOCK_TAGS.join(",")).each do |node|
        node.add_previous_sibling("\n")
        node.add_next_sibling("\n")
      end

      fragment.text
              .tr("\u00a0", " ")
              .gsub(/[ \t\r\f\v]+/, " ")
              .gsub(/ *\n */, "\n")
              .gsub(/\n{3,}/, "\n\n")
              .strip
    rescue Nokogiri::XML::SyntaxError
      value.to_s.squish
    end
  end
end

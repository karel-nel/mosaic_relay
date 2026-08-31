# frozen_string_literal: true

module MosaicRelay
  # Relay owns the public widget implementation. This module keeps script
  # loading under gem control while allowing a trusted administrator to supply
  # Relay's mount markup.
  module WidgetMarkup
    SCRIPT_TAG = %r{<script\b[^>]*>.*?</script\s*>}im
    SRC_ATTRIBUTE = %r{\bsrc\s*=\s*(["'])(.*?)\1}im
    RELAY_URL_ATTRIBUTE = %r{\brelay-url\s*=\s*(["'])(.*?)\1}im

    module_function

    def mount_markup(markup)
      markup.to_s.gsub(SCRIPT_TAG, "").strip
    end

    def script_url(markup)
      source = markup.to_s.match(SCRIPT_TAG)&.to_s&.match(SRC_ATTRIBUTE)&.captures&.last
      return source if public_url?(source)

      relay_url = markup.to_s.match(RELAY_URL_ATTRIBUTE)&.captures&.last
      return unless public_url?(relay_url)

      "#{relay_url.sub(%r{/+\z}, "")}/niimble-relay-widget.js"
    end

    def public_url?(value)
      value.to_s.match?(%r{\Ahttps?://}i)
    end
    private_class_method :public_url?
  end
end

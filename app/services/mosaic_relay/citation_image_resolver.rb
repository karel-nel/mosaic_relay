# frozen_string_literal: true

require "digest"
require "net/http"
require "uri"

module MosaicRelay
  # Resolves trusted citation pages' Open Graph images on the server. Browsers
  # cannot reliably read another page's <meta property="og:image"> tags.
  class CitationImageResolver
    MAX_CITATIONS = 6
    CACHE_TTL = 12.hours
    OPEN_TIMEOUT = 1
    READ_TIMEOUT = 2

    def self.enrich(payload)
      citations = Array(payload["citations"])
      return payload if citations.empty?

      payload.merge(
        "citations" => citations.each_with_index.map do |citation, index|
          index < MAX_CITATIONS ? enrich_citation(citation) : citation
        end
      )
    end

    def self.enrich_citation(citation)
      citation = citation.deep_stringify_keys
      return citation if citation["image_url"].present?

      image_url = image_for(citation["url"])
      image_url.present? ? citation.merge("image_url" => image_url) : citation
    end
    private_class_method :enrich_citation

    def self.image_for(url)
      uri = safe_page_uri(url)
      return unless uri

      Rails.cache.fetch("relay/citation-image/#{Digest::SHA256.hexdigest(uri.to_s)}", expires_in: CACHE_TTL) do
        extract_open_graph_image(uri)
      end
    end
    private_class_method :image_for

    def self.safe_page_uri(url)
      uri = URI.parse(url.to_s)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?

      trusted_host = URI.parse(MosaicRelay.configuration.public_base_url).host
      return unless trusted_host.present? && uri.host.casecmp?(trusted_host)

      uri
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :safe_page_uri

    def self.extract_open_graph_image(uri)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "text/html,application/xhtml+xml"
        http.request(request)
      end
      return unless response.is_a?(Net::HTTPSuccess) && response["content-type"].to_s.include?("html")

      meta_tags = response.body.to_s.byteslice(0, 128.kilobytes).scan(/<meta\b[^>]*>/i)
      image_tag = meta_tags.find { |tag| tag.match?(/\b(?:property|name)\s*=\s*["'](?:og:image|twitter:image)["']/i) }
      image_url = html_attribute(image_tag, "content")
      return if image_url.blank?

      resolved = URI.join(uri.to_s, image_url)
      resolved.is_a?(URI::HTTP) ? resolved.to_s : nil
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, URI::InvalidURIError
      nil
    end
    private_class_method :extract_open_graph_image

    def self.html_attribute(tag, name)
      tag.to_s[/\b#{Regexp.escape(name)}\s*=\s*["']([^"']+)["']/i, 1]
    end
    private_class_method :html_attribute
  end
end

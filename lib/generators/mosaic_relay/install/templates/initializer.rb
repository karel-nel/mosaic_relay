# frozen_string_literal: true

# MosaicRelay reads its credentials and defaults from RELAY_* environment
# variables. Override only application-specific model or infrastructure adapters
# here; never commit Relay credentials to source control.
MosaicRelay.configure do |config|
  # config.page_model = Page
  # config.blog_model = Blog
  # config.page_element_model = PageElement
  # config.redis = Redis.new(url: ENV.fetch("REDIS_URL"))
  # config.asset_url_builder = ->(blob) { "https://cdn.example/#{blob.key}" }
  # config.blog_path_builder = ->(blog) { "/blog/#{ERB::Util.url_encode(blog.slug)}" }
end

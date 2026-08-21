module MosaicRelay
  class Configuration
    DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS = 5
    DEFAULT_CHAT_READ_TIMEOUT_SECONDS = 45
    DEFAULT_LANGUAGE = "en"
    DEFAULT_PAGE_SIZE = 25

    attr_accessor :source_token,
                  :public_base_url,
                  :chat_base_url,
                  :chat_token,
                  :chat_tenant_key,
                  :chat_open_timeout_seconds,
                  :chat_read_timeout_seconds,
                  :default_language,
                  :page_size,
                  :redis,
                  :broadcaster,
                  :pod_schema_resolver,
                  :asset_url_builder,
                  :page_model,
                  :blog_model,
                  :page_element_model

    def self.from_env(env = ENV)
      new(
        source_token: env["RELAY_SOURCE_TOKEN"],
        public_base_url: env.fetch("RELAY_PUBLIC_BASE_URL", ""),
        chat_base_url: env.fetch("RELAY_CHAT_BASE_URL", ""),
        chat_token: env["RELAY_CHAT_TOKEN"],
        chat_tenant_key: env.fetch("RELAY_CHAT_TENANT_KEY", "mosaic"),
        chat_open_timeout_seconds: env.fetch("RELAY_CHAT_OPEN_TIMEOUT_SECONDS", DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS),
        chat_read_timeout_seconds: env.fetch("RELAY_CHAT_READ_TIMEOUT_SECONDS", DEFAULT_CHAT_READ_TIMEOUT_SECONDS),
        default_language: env.fetch("RELAY_DEFAULT_LANGUAGE", DEFAULT_LANGUAGE),
        page_size: env.fetch("RELAY_DOCUMENTS_PAGE_SIZE", DEFAULT_PAGE_SIZE)
      )
    end

    def initialize(source_token: nil, public_base_url: "", chat_base_url: "", chat_token: nil,
                   chat_tenant_key: "mosaic", chat_open_timeout_seconds: DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS,
                   chat_read_timeout_seconds: DEFAULT_CHAT_READ_TIMEOUT_SECONDS, default_language: DEFAULT_LANGUAGE,
                   page_size: DEFAULT_PAGE_SIZE, redis: nil, broadcaster: nil, pod_schema_resolver: nil,
                   asset_url_builder: nil, page_model: nil, blog_model: nil, page_element_model: nil)
      @source_token = source_token
      @public_base_url = public_base_url
      @chat_base_url = chat_base_url
      @chat_token = chat_token
      @chat_tenant_key = chat_tenant_key
      @chat_open_timeout_seconds = chat_open_timeout_seconds
      @chat_read_timeout_seconds = chat_read_timeout_seconds
      @default_language = default_language
      @page_size = page_size
      @redis = redis
      @broadcaster = broadcaster
      @pod_schema_resolver = pod_schema_resolver
      @asset_url_builder = asset_url_builder
      @page_model = page_model
      @blog_model = blog_model
      @page_element_model = page_element_model
    end

    def public_base_url
      strip_trailing_slashes(@public_base_url)
    end

    def chat_base_url
      strip_trailing_slashes(@chat_base_url)
    end

    def chat_tenant_key
      @chat_tenant_key.to_s.parameterize.presence || "mosaic"
    end

    def chat_open_timeout_seconds
      bounded_integer(@chat_open_timeout_seconds, default: DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS, min: 1, max: 30)
    end

    def chat_read_timeout_seconds
      bounded_integer(@chat_read_timeout_seconds, default: DEFAULT_CHAT_READ_TIMEOUT_SECONDS, min: 1, max: 120)
    end

    def page_size
      bounded_integer(@page_size, default: DEFAULT_PAGE_SIZE, min: 1, max: 250)
    end

    private

    def strip_trailing_slashes(value)
      value.to_s.sub(%r{/+\z}, "")
    end

    def bounded_integer(value, default:, min:, max:)
      Integer(value).clamp(min, max)
    rescue ArgumentError, TypeError
      default
    end
  end
end

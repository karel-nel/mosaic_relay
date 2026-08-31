module MosaicRelay
  class Configuration
    DEFAULT_LANGUAGE = "en"
    DEFAULT_PAGE_SIZE = 25

    attr_accessor :source_token,
                  :public_base_url,
                  :widget_markup,
                  :default_language,
                  :page_size,
                  :source_types,
                  :source_field_mappings,
                  :pod_schema_resolver,
                  :asset_url_builder,
                  :blog_path_builder,
                  :page_path_builder,
                  :source_provider,
                  :page_model,
                  :blog_model,
                  :page_element_model

    ADAPTER_ATTRIBUTES = %i[
      pod_schema_resolver asset_url_builder blog_path_builder page_path_builder source_provider
      page_model blog_model page_element_model
    ].freeze

    def self.from_settings(settings = nil)
      return new unless RelaySetting.table_available?

      settings ||= RelaySetting.current
      new(
        source_token: settings.source_token,
        public_base_url: settings.public_base_url,
        widget_markup: settings.widget_markup,
        default_language: settings.default_language,
        page_size: settings.page_size,
        source_types: settings.source_types,
        source_field_mappings: settings.source_field_mappings
      )
    end

    def initialize(source_token: nil, public_base_url: "", widget_markup: "", default_language: DEFAULT_LANGUAGE,
                   page_size: DEFAULT_PAGE_SIZE, source_types: nil, source_field_mappings: {}, pod_schema_resolver: nil,
                   asset_url_builder: nil, blog_path_builder: nil, page_path_builder: nil, source_provider: nil,
                   page_model: nil, blog_model: nil, page_element_model: nil)
      @source_token = source_token
      @public_base_url = public_base_url
      @widget_markup = widget_markup
      @default_language = default_language
      @page_size = page_size
      @source_types = source_types.nil? ? nil : Array(source_types).map(&:to_s) & SourceRegistry.keys
      @source_field_mappings = SourceRegistry.normalize_field_mappings(source_field_mappings)
      @pod_schema_resolver = pod_schema_resolver
      @asset_url_builder = asset_url_builder
      @blog_path_builder = blog_path_builder
      @page_path_builder = page_path_builder
      @source_provider = source_provider
      @page_model = page_model
      @blog_model = blog_model
      @page_element_model = page_element_model
    end

    def public_base_url
      strip_trailing_slashes(@public_base_url)
    end

    def page_size
      bounded_integer(@page_size, default: DEFAULT_PAGE_SIZE, min: 1, max: 250)
    end

    def source_types
      @source_types.nil? ? SourceRegistry.default_source_types : @source_types
    end

    def source_field_mappings
      @source_field_mappings || {}
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

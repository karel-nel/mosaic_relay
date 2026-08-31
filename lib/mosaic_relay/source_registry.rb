# frozen_string_literal: true

module MosaicRelay
  # Explicit public-content catalog for Relay. It keeps source discovery
  # conservative: only Mosaic's Pages and Blogs are built in, while hosts can
  # register additional source contracts rather than exposing arbitrary tables.
  class SourceRegistry
    Source = Struct.new(
      :key, :label, :description, :model_name, :model_resolver, :fields, :field_options,
      :title, :collection_path, :record_path, :scope, :content_type,
      keyword_init: true
    ) do
      def model
        model_resolver&.call || model_name.to_s.safe_constantize
      rescue StandardError
        nil
      end

      def available?
        klass = model
        klass && klass.respond_to?(:table_exists?) && klass.table_exists?
      rescue StandardError
        false
      end

      def definition
        {
          model: model_name,
          title: title,
          fields: Array(fields),
          field_options: Array(field_options),
          collection_path: collection_path,
          record_path: record_path,
          scope: scope,
          content_type: content_type
        }
      end

      def public_path_for(record)
        path = record_path.respond_to?(:call) ? record_path.call(record) : record_path
        path.presence || collection_path
      rescue StandardError
        nil
      end
    end

    SourceStatus = Struct.new(:source, :ingestible, :reason, :endpoint, keyword_init: true) do
      def ingestible?
        ingestible
      end
    end

    DEFAULT_SOURCE_TYPES = %w[pages blogs].freeze
    SOURCE_KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/.freeze
    TITLE_FIELDS = %w[title name question subject headline].freeze
    NON_CONTENT_FIELDS = %w[id created_at updated_at published_at slug ancestry].freeze

    class << self
      def register(attributes)
        source = build_source(attributes)
        raise ArgumentError, "Source keys must use lowercase letters, numbers, and underscores" unless source.key.match?(SOURCE_KEY_PATTERN)
        raise ArgumentError, "#{source.key} is a built-in Mosaic Relay source" if DEFAULT_SOURCE_TYPES.include?(source.key)

        registered_sources[source.key] = source
        source
      end

      def default_source_types
        DEFAULT_SOURCE_TYPES
      end

      def known
        sources = { "pages" => page_source, "blogs" => blog_source }
        dynamic_sources.each { |source| sources[source.key] ||= source }
        registered_sources.each { |key, source| sources[key] = source }
        sources.values.compact.sort_by { |source| [ source.key == "pages" ? 0 : 1, source.key ] }
      end

      def keys
        known.map(&:key)
      end

      def fetch(key)
        known.find { |source| source.key == key.to_s }
      end

      def source_type_for(model)
        model_name = model.respond_to?(:name) ? model.name.to_s : model.to_s
        known.find { |source| source.model_name == model_name }&.key
      end

      def reset!
        @registered_sources = {}
      end

      def source_statuses(host: nil, protocol: "http")
        known.map { |source| source_status(source, host: host, protocol: protocol) }
      end

      def options(host: nil, protocol: "http")
        source_statuses(host: host, protocol: protocol).select(&:ingestible?).map(&:source)
      end

      def source_status(source, host: nil, protocol: "http")
        return unavailable(source, "the Mosaic model is not available") unless source&.available?
        return unavailable(source, "does not declare a public content scope") if source.scope.blank?
        return unavailable(source, "does not declare a public collection URL") if source.collection_path.blank?
        return unavailable(source, "does not declare a public record URL") if source.record_path.blank?

        collection_endpoint = PublicEndpointValidator.call(path: source.collection_path, host: host, protocol: protocol)
        return unavailable(source, collection_endpoint.reason, collection_endpoint) unless collection_endpoint.available?

        record = representative_record(source)
        return unavailable(source, "has no public records to validate", collection_endpoint) unless record

        record_path = source.public_path_for(record)
        return unavailable(source, "could not derive a public record URL", collection_endpoint) if record_path.blank?

        record_endpoint = PublicEndpointValidator.call(path: record_path, host: host, protocol: protocol)
        return SourceStatus.new(source: source, ingestible: true, endpoint: record_endpoint) if record_endpoint.available?

        unavailable(source, record_endpoint.reason, record_endpoint)
      rescue StandardError => error
        unavailable(source, "could not be checked (#{error.class})")
      end

      # Only source-defined text fields can reach Relay. This is used both by
      # the settings form and feed configuration, so stale or forged form
      # values cannot expand the data boundary.
      def normalize_field_mappings(mappings)
        Hash(mappings || {}).each_with_object({}) do |(key, fields), normalized|
          source = fetch(key)
          next unless source

          allowed = Array(source.field_options).map(&:to_s)
          selected = Array(fields).map(&:to_s).select { |field| allowed.include?(field) }.uniq
          normalized[source.key] = selected if selected.present?
        end
      rescue TypeError
        {}
      end

      def public_records(source)
        return unless source

        model = source.model
        source.scope.respond_to?(:call) ? source.scope.call(model) : model.public_send(source.scope)
      rescue ActiveRecord::StatementInvalid, NoMethodError
        nil
      end

      def public_record?(source, record)
        return false unless source && record

        records = public_records(source)
        return false unless records

        if records.respond_to?(:exists?)
          records.where(id: record.id).exists?
        else
          records.any? { |candidate| candidate.id == record.id }
        end
      rescue ActiveRecord::StatementInvalid, NoMethodError
        false
      end

      private

      def registered_sources
        @registered_sources ||= {}
      end

      def dynamic_sources
        provider = MosaicRelay.adapter_configuration&.source_provider
        return [] unless provider.respond_to?(:call)

        Array(provider.call).filter_map do |attributes|
          next attributes if attributes.is_a?(Source)

          source = build_source(attributes.to_h.symbolize_keys)
          next if DEFAULT_SOURCE_TYPES.include?(source.key)
          next unless source.key.match?(SOURCE_KEY_PATTERN)

          source
        end
      rescue StandardError
        []
      end

      def unavailable(source, reason, endpoint = nil)
        SourceStatus.new(source: source, ingestible: false, reason: reason, endpoint: endpoint)
      end

      def representative_record(source)
        records = public_records(source)
        return unless records

        records = records.order(:id) if records.respond_to?(:order)
        records.first
      rescue ActiveRecord::StatementInvalid, NoMethodError
        nil
      end

      def page_source
        model = page_model
        return unless model

        fields = [ "content", *selectable_fields(model, %w[menu_title meta_description]) ]
        build_source(
          key: "pages",
          label: "Pages",
          description: "Published pages and their Pod content",
          model: model,
          fields: fields,
          field_options: fields,
          title: :title,
          collection_path: "/",
          record_path: lambda { |page|
            page_path_for(page)
          },
          scope: :published,
          content_type: "page"
        )
      end

      def blog_source
        model = blog_model
        return unless model

        fields = [ "content", *selectable_fields(model, %w[excerpt seo_title seo_description]) ]
        build_source(
          key: "blogs",
          label: "Blogs",
          description: "Published blog posts and rich content",
          model: model,
          fields: fields,
          field_options: fields,
          title: :title,
          collection_path: blog_collection_path,
          record_path: lambda { |blog|
            blog_path_for(blog)
          },
          scope: ->(relation) { relation.visible.published },
          content_type: "article"
        )
      end

      def page_model
        MosaicRelay.adapter_configuration&.page_model || (defined?(::Page) ? ::Page : nil)
      end

      def blog_model
        MosaicRelay.adapter_configuration&.blog_model || (defined?(::Blog) ? ::Blog : nil)
      end

      def selectable_fields(model, preferred)
        available = model.respond_to?(:column_names) ? model.column_names.map(&:to_s) : []
        preferred.select { |field| available.include?(field) && !NON_CONTENT_FIELDS.include?(field) }
      rescue StandardError
        []
      end

      def page_path_for(page)
        builder = MosaicRelay.configuration.page_path_builder
        return builder.call(page) if builder.respond_to?(:call)

        page.slug.to_s == "home" ? "/" : "/#{ERB::Util.url_encode(page.slug)}"
      end

      def blog_collection_path
        route_path(:blogs_path) || "/blogs"
      end

      def blog_path_for(blog)
        route_path(:blog_path, blog) || "/blogs/#{ERB::Util.url_encode(blog.slug)}"
      end

      def route_path(helper, *arguments)
        return unless defined?(Rails) && Rails.application

        routes = Rails.application.routes.url_helpers
        return unless routes.respond_to?(helper)

        routes.public_send(helper, *arguments)
      rescue StandardError
        nil
      end

      def build_source(attributes)
        model = attributes[:model]
        model_name = attributes[:model_name].presence || (model.respond_to?(:name) ? model.name.to_s : model.to_s)
        key = attributes.fetch(:key).to_s
        resolved_model = model.respond_to?(:call) ? nil : model
        Source.new(
          key: key,
          label: attributes.fetch(:label, key.humanize),
          description: attributes.fetch(:description, "#{key.humanize} content"),
          model_name: model_name,
          model_resolver: model.respond_to?(:call) ? model : -> { model },
          fields: Array(attributes[:fields]),
          field_options: Array(attributes.fetch(:field_options, attributes[:fields])),
          title: attributes.fetch(:title, selectable_title(resolved_model)),
          collection_path: attributes[:collection_path],
          record_path: attributes[:record_path],
          scope: attributes[:scope],
          content_type: attributes.fetch(:content_type, key.singularize)
        )
      end

      def selectable_title(model)
        return :title unless model.respond_to?(:column_names)

        TITLE_FIELDS.find { |field| model.column_names.map(&:to_s).include?(field) }&.to_sym
      rescue StandardError
        :title
      end
    end
  end
end

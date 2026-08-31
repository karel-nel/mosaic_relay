# frozen_string_literal: true

module MosaicRelay
  class DocumentFeed
    SNAPSHOT_PHASES = %w[pages blogs].freeze

    def initialize(cursor:, page_size: nil, public_base_url: nil)
      @cursor = CursorCodec.decode(cursor)
      @page_size = page_size.nil? ? configuration.page_size : page_size.to_i
      @source_types = configuration.source_types
      @source_field_mappings = configuration.source_field_mappings
      @public_base_url = public_base_url.to_s.strip.presence || configuration.public_base_url
    end

    def call
      return initial_snapshot if cursor.blank?

      case cursor.fetch("mode")
      when "snapshot" then snapshot_page(cursor)
      when "events" then event_page(cursor)
      else raise CursorCodec::InvalidCursor
      end
    rescue KeyError
      raise CursorCodec::InvalidCursor
    end

    private

    attr_reader :cursor, :page_size, :source_field_mappings, :public_base_url

    def source_types
      @source_types || SNAPSHOT_PHASES
    end

    def initial_snapshot
      if source_types.empty?
        cursor = CursorCodec.encode("mode" => "events", "after" => DocumentChange.maximum(:id).to_i)
        return envelope([], cursor: cursor)
      end

      snapshot_page(
        "mode" => "snapshot",
        "phase" => source_types.first,
        "last_id" => 0,
        "high_water" => DocumentChange.maximum(:id).to_i
      )
    end

    def snapshot_page(state)
      phase = state.fetch("phase")
      raise CursorCodec::InvalidCursor unless source_types.include?(phase)

      documents = []
      current_phase = phase
      last_id = cursor_integer(state.fetch("last_id", 0))

      while documents.length < page_size && current_phase.present?
        records = snapshot_records(current_phase, last_id)
        records.each do |record|
          last_id = record.id
          document = serialize_snapshot_record(record, current_phase)
          documents << document if document.present?
          break if documents.length == page_size
        end

        next if records.length == page_size

        current_phase = next_phase(current_phase)
        last_id = 0
      end

      if current_phase.present?
        next_cursor = CursorCodec.encode(
          "mode" => "snapshot",
          "phase" => current_phase,
          "last_id" => last_id,
          "high_water" => state.fetch("high_water")
        )
        envelope(documents, cursor: next_cursor, next_cursor: next_cursor)
      else
        final_cursor = CursorCodec.encode("mode" => "events", "after" => state.fetch("high_water").to_i)
        envelope(documents, cursor: final_cursor)
      end
    end

    def event_page(state)
      after = cursor_integer(state.fetch("after", 0))
      changes = DocumentChange.after_sequence(after).ordered.to_a
      changes = changes.select do |change|
        change.deleted? || source_types.any? { |source| change.external_id.to_s.start_with?("#{source}:") }
      end
      changes = changes.first(page_size)
      documents = changes.map { |change| document_for_change(change) }
      checkpoint = changes.last&.id || after
      next_cursor = if changes.length == page_size
        CursorCodec.encode("mode" => "events", "after" => checkpoint)
      end
      checkpoint_cursor = CursorCodec.encode("mode" => "events", "after" => checkpoint)

      envelope(documents, cursor: checkpoint_cursor, next_cursor: next_cursor)
    end

    def snapshot_records(phase, last_id)
      scope = snapshot_scope(phase, last_id)
      return [] unless scope

      scope.limit(page_size).to_a
    end

    def snapshot_scope(phase, last_id)
      source = SourceRegistry.fetch(phase)
      model = source&.model
      return unless source && model

      scope = SourceRegistry.public_records(source)
      scope = apply_after_id(scope, model, last_id)
      scope = scope.includes(*blog_association_names(model)) if phase == "blogs" && scope.respond_to?(:includes) && blog_association_names(model).any?
      scope = scope.with_rich_text_content if phase == "blogs" && scope.respond_to?(:with_rich_text_content)
      scope.order(:id)
    rescue ActiveRecord::StatementInvalid, NoMethodError
      nil
    end

    def serialize_snapshot_record(record, phase)
      source = SourceRegistry.fetch(phase)
      fields = fields_for(source)

      case phase
      when "pages" then DocumentSerializer.for_page(record, fields: fields, public_base_url: public_base_url)
      when "blogs" then DocumentSerializer.for_blog(record, fields: fields, public_base_url: public_base_url)
      else
        DocumentSerializer.for_source(record, source, fields: fields, public_base_url: public_base_url)
      end
    end

    def next_phase(phase)
      source_types[source_types.index(phase) + 1]
    end

    def envelope(documents, cursor:, next_cursor: nil)
      payload = { "documents" => documents, "cursor" => cursor }
      payload["next_cursor"] = next_cursor if next_cursor.present?
      payload
    end

    def cursor_integer(value)
      Integer(value)
    rescue ArgumentError, TypeError
      raise CursorCodec::InvalidCursor
    end

    def page_model
      configuration.page_model || (defined?(::Page) ? ::Page : nil)
    end

    def blog_model
      configuration.blog_model || (defined?(::Blog) ? ::Blog : nil)
    end

    def configuration
      MosaicRelay.configuration
    end

    def blog_association_names(model)
      return [] unless model.respond_to?(:reflect_on_association)

      %i[
        blog_category blog_categories blog_tags blog_taggings
        blog_category_assignments blog_legacy_redirects
      ].select { |name| model.reflect_on_association(name) }
    end

    def apply_after_id(scope, model, last_id)
      return scope.where(model.arel_table[:id].gt(last_id)) if model.respond_to?(:arel_table)

      scope.where("id > ?", last_id)
    end

    def fields_for(source)
      selected = source_field_mappings[source.key]
      selected.present? ? selected.map(&:to_sym) : Array(source.fields).map(&:to_sym)
    end

    def document_for_change(change)
      return tombstone(change) if change.deleted?

      source_key = change.external_id.to_s.split(":", 2).first
      if %w[pages blogs].include?(source_key)
        source = SourceRegistry.fetch(source_key)
        return DocumentSerializer.for_change(change, fields: fields_for(source), public_base_url: public_base_url)
      end

      source = SourceRegistry.fetch(source_key) || SourceRegistry.fetch(SourceRegistry.source_type_for(change.resource_type))
      return DocumentSerializer.for_change(change, public_base_url: public_base_url) unless source

      record = source.model&.find_by(id: change.resource_id)
      return tombstone(change) unless SourceRegistry.public_record?(source, record)

      DocumentSerializer.for_source(record, source, fields: fields_for(source), public_base_url: public_base_url) || { "external_id" => change.external_id, "deleted" => true }
    rescue ActiveRecord::StatementInvalid, NoMethodError
      { "external_id" => change.external_id, "deleted" => true }
    end

    def tombstone(change)
      { "external_id" => change.external_id, "deleted" => true }
    end
  end
end

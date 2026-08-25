# frozen_string_literal: true

module MosaicRelay
  class DocumentFeed
    SNAPSHOT_PHASES = %w[pages blogs].freeze

    def initialize(cursor:, page_size: nil)
      @cursor = CursorCodec.decode(cursor)
      @page_size = page_size.nil? ? configuration.page_size : page_size.to_i
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

    attr_reader :cursor, :page_size

    def initial_snapshot
      snapshot_page(
        "mode" => "snapshot",
        "phase" => "pages",
        "last_id" => 0,
        "high_water" => DocumentChange.maximum(:id).to_i
      )
    end

    def snapshot_page(state)
      phase = state.fetch("phase")
      raise CursorCodec::InvalidCursor unless SNAPSHOT_PHASES.include?(phase)

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
      changes = DocumentChange.after_sequence(after).ordered.limit(page_size).to_a
      documents = changes.map { |change| DocumentSerializer.for_change(change) }
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
      case phase
      when "pages"
        model = page_model
        return unless model

        model.published.where("pages.id > ?", last_id).order(:id)
      when "blogs"
        model = blog_model
        return unless model

        scope = model.visible.published.where("blogs.id > ?", last_id)
        scope = scope.includes(*blog_association_names(model)) if scope.respond_to?(:includes) && blog_association_names(model).any?
        scope = scope.with_rich_text_content if scope.respond_to?(:with_rich_text_content)
        scope.order(:id)
      end
    end

    def serialize_snapshot_record(record, phase)
      case phase
      when "pages" then DocumentSerializer.for_page(record)
      when "blogs" then DocumentSerializer.for_blog(record)
      end
    end

    def next_phase(phase)
      SNAPSHOT_PHASES[SNAPSHOT_PHASES.index(phase) + 1]
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
  end
end

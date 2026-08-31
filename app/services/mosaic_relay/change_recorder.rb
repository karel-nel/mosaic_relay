# frozen_string_literal: true

module MosaicRelay
  class ChangeRecorder
    class << self
      def record_page(page_or_id, occurred_at: Time.current)
        record_resource("pages", "Page", page_or_id, occurred_at: occurred_at)
      end

      def record_blog(blog_or_id, occurred_at: Time.current)
        record_resource("blogs", "Blog", blog_or_id, occurred_at: occurred_at)
      end

      # Custom registered sources opt into the existing change ledger by
      # calling this from their host application's model callback.
      def record_source(source_key, resource_or_id, occurred_at: Time.current)
        source = SourceRegistry.fetch(source_key)
        return unless source

        record_resource(source.key, source.model_name, resource_or_id, occurred_at: occurred_at)
      end

      def record(external_id:, resource_type:, resource_id:, occurred_at: Time.current, deleted: false)
        return if external_id.blank?

        DocumentChange.create!(
          external_id: external_id,
          resource_type: resource_type,
          resource_id: resource_id,
          occurred_at: occurred_at,
          deleted: deleted
        )
      end

      def record_source_documents(source_key, occurred_at: Time.current)
        source = SourceRegistry.fetch(source_key)
        return unless source

        each_public_record(source) do |record|
          record_resource(source.key, source.model_name, record, occurred_at: occurred_at)
        end
      end

      def record_source_tombstones(source_key, occurred_at: Time.current)
        source = SourceRegistry.fetch(source_key)
        return unless source

        each_public_record(source) do |record|
          resource_id = record.id
          record(
            external_id: MigrationContract.external_id(source.key, resource_id),
            resource_type: source.model_name,
            resource_id: resource_id,
            occurred_at: occurred_at,
            deleted: true
          )
        end
      end

      private

      def record_resource(prefix, resource_type, resource_or_id, occurred_at:)
        resource_id = resource_or_id.respond_to?(:id) ? resource_or_id.id : resource_or_id
        return if resource_id.blank?

        record(
          external_id: MigrationContract.external_id(prefix, resource_id),
          resource_type: resource_type,
          resource_id: resource_id,
          occurred_at: occurred_at
        )
      end

      def each_public_record(source, &block)
        records = SourceRegistry.public_records(source)
        return unless records

        if records.respond_to?(:find_each)
          records.find_each(&block)
        else
          records.each(&block)
        end
      rescue ActiveRecord::StatementInvalid, NoMethodError
        nil
      end
    end
  end
end

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

      def record(external_id:, resource_type:, resource_id:, occurred_at: Time.current)
        return if external_id.blank?

        DocumentChange.create!(
          external_id: external_id,
          resource_type: resource_type,
          resource_id: resource_id,
          occurred_at: occurred_at
        )
      end

      private

      def record_resource(prefix, resource_type, resource_or_id, occurred_at:)
        resource_id = resource_or_id.respond_to?(:id) ? resource_or_id.id : resource_or_id
        return if resource_id.blank?

        record(
          external_id: "#{prefix}:#{resource_id}",
          resource_type: resource_type,
          resource_id: resource_id,
          occurred_at: occurred_at
        )
      end
    end
  end
end

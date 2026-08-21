# frozen_string_literal: true

module MosaicRelay
  class PageChangeTracker
    class << self
      def record_page(page_id)
        ChangeRecorder.record_page(page_id) if page_id.present?
      end

      def record_for_pod(pod)
        page_ids_for_pod(pod).uniq.each { |page_id| record_page(page_id) }
      end

      def page_ids_for_pod(pod)
        page_ids = if pod.respond_to?(:page_pods)
          pod.page_pods.pluck(:page_id)
        else
          []
        end

        element_model = configuration.page_element_model || default_page_element_model
        if element_model && pod.respond_to?(:id)
          page_ids.concat(
            element_model.joins(page_section_slot: { page_section: :page_composition })
                         .where(pod_id: pod.id)
                         .pluck("page_compositions.page_id")
          )
        end

        page_ids.compact.uniq
      end

      private

      def configuration
        MosaicRelay.configuration
      end

      def default_page_element_model
        defined?(::PageElement) ? ::PageElement : nil
      end
    end
  end
end

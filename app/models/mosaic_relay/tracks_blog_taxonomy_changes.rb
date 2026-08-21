# frozen_string_literal: true

module MosaicRelay
  module TracksBlogTaxonomyChanges
    extend ActiveSupport::Concern

    included do
      after_commit :record_mosaic_relay_associated_blog_changes, on: [ :update ]
    end

    private

    def record_mosaic_relay_associated_blog_changes
      associated_blog_relations.flat_map { |relation| relation.pluck(:id) }.uniq.each do |blog_id|
        MosaicRelay::ChangeRecorder.record_blog(blog_id)
      end
    end

    def associated_blog_relations
      %i[blogs categorized_blogs].filter_map do |association|
        public_send(association) if respond_to?(association)
      end
    end
  end
end

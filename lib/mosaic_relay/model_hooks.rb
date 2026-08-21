# frozen_string_literal: true

module MosaicRelay
  module ModelHooks
    MODEL_CONCERNS = {
      "Page" => "MosaicRelay::TracksPageDocumentChanges",
      "Blog" => "MosaicRelay::TracksBlogDocumentChanges",
      "Pod" => "MosaicRelay::TracksPodChanges",
      "PagePod" => "MosaicRelay::TracksAssociatedPageChanges",
      "PageComposition" => "MosaicRelay::TracksAssociatedPageChanges",
      "PageSection" => "MosaicRelay::TracksAssociatedPageChanges",
      "PageSectionSlot" => "MosaicRelay::TracksAssociatedPageChanges",
      "PageElement" => "MosaicRelay::TracksAssociatedPageChanges",
      "BlogTag" => "MosaicRelay::TracksBlogTaxonomyChanges",
      "BlogCategory" => "MosaicRelay::TracksBlogTaxonomyChanges",
      "BlogTagging" => "MosaicRelay::TracksBlogAssociationChanges",
      "BlogCategoryAssignment" => "MosaicRelay::TracksBlogAssociationChanges"
    }.freeze

    module_function

    def install!
      MODEL_CONCERNS.each do |model_name, concern_name|
        concern = concern_name.constantize
        model = configured_model(model_name) || model_name.safe_constantize
        model.include(concern) if model && !(model < concern)
      end
    end

    def configured_model(model_name)
      case model_name
      when "Page"
        MosaicRelay.configuration.page_model
      when "Blog"
        MosaicRelay.configuration.blog_model
      end
    end
  end
end

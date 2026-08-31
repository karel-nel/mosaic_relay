# frozen_string_literal: true

module MosaicRelay
  class DocumentChange < ApplicationRecord
    self.table_name = "mosaic_relay_document_changes"

    validates :external_id, :resource_type, :occurred_at, presence: true

    scope :after_sequence, ->(sequence) { where("id > ?", sequence.to_i) }
    scope :ordered, -> { order(:id) }

    def deleted?
      self[:deleted] == true
    end
  end
end

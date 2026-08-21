# frozen_string_literal: true

module MosaicRelay
  class RelayChatChannel < ApplicationCable::Channel
    def subscribed
      stream_from MosaicRelay::CreditAvailability.stream_name
    end
  end
end

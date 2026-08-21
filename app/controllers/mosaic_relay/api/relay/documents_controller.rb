# frozen_string_literal: true

require "digest"

module MosaicRelay
  module Api
    module Relay
      class DocumentsController < ActionController::API
        before_action :authenticate_source!

        def index
          render json: MosaicRelay::DocumentFeed.new(cursor: params[:cursor]).call
        rescue MosaicRelay::CursorCodec::InvalidCursor
          render json: { error: "invalid_cursor", message: "cursor is invalid" }, status: :unprocessable_entity
        end

        private

        def authenticate_source!
          token = MosaicRelay.configuration.source_token.to_s
          supplied_token = bearer_token

          return if token.present? && supplied_token.present? && secure_token_match?(token, supplied_token)

          render json: { error: "unauthorized", message: "A valid Relay source token is required." }, status: :unauthorized
        end

        def bearer_token
          scheme, token = request.authorization.to_s.split(" ", 2)
          return unless scheme&.casecmp?("Bearer")

          token.to_s.strip.presence
        end

        def secure_token_match?(expected, supplied)
          ActiveSupport::SecurityUtils.secure_compare(
            Digest::SHA256.hexdigest(expected),
            Digest::SHA256.hexdigest(supplied)
          )
        end
      end
    end
  end
end

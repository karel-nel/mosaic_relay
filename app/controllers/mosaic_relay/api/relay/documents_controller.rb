# frozen_string_literal: true

require "digest"
require "uri"

module MosaicRelay
  module Api
    module Relay
      class DocumentsController < ActionController::API
        before_action :ensure_configured
        before_action :authenticate_source!

        def index
          render json: MosaicRelay::DocumentFeed.new(
            cursor: params[:cursor],
            public_base_url: source_base_url
          ).call
        rescue MosaicRelay::CursorCodec::InvalidCursor
          render json: { error: "invalid_cursor", message: "cursor is invalid" }, status: :unprocessable_entity
        end

        private

        def ensure_configured
          return if MosaicRelay.configuration.source_token.present?

          render json: { error: "source_not_configured" }, status: :service_unavailable
        end

        def source_base_url
          configured = MosaicRelay.configuration.public_base_url.to_s.strip
          return configured if absolute_http_url?(configured)

          protocol = request.ssl? ? "https" : "http"
          "#{protocol}://#{request.host_with_port}"
        end

        def absolute_http_url?(value)
          uri = URI.parse(value)
          uri.is_a?(URI::HTTP) && uri.host.present?
        rescue URI::InvalidURIError
          false
        end

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

# frozen_string_literal: true

module MosaicRelay
  module Api
    module Relay
      class ChatsController < ActionController::API
        def availability
          render json: { available: MosaicRelay::CreditAvailability.available? }
        rescue MosaicRelay::CreditAvailability::CacheUnavailable
          render json: { available: false }
        end

        def create
          conversation_id = params[:conversation_id].presence
          return render_unavailable unless conversation_id || MosaicRelay::CreditAvailability.available?

          result = MosaicRelay::ChatClient.call(
            conversation_id:,
            message: params.require(:message).to_s.strip,
            visitor_id: params[:visitor_id],
            context: context_params
          )

          return render_unavailable if credit_limit_exhausted?(result)

          render json: result.payload, status: result.status
        rescue ActionController::ParameterMissing
          render json: { error: "invalid_request", message: "message is required" }, status: :unprocessable_entity
        rescue MosaicRelay::CreditAvailability::CacheUnavailable
          render_unavailable
        rescue MosaicRelay::ChatClient::ConfigurationError, MosaicRelay::ChatClient::UpstreamError => e
          render json: { error: "chat_unavailable", message: e.message }, status: :service_unavailable
        end

        private

        def context_params
          params.fetch(:context, {}).permit(:current_url, :locale, :interface, :interface_type).to_h
        end

        def credit_limit_exhausted?(result)
          return false unless result.status == 429 && result.payload["error"] == "credit_limit_exhausted"

          MosaicRelay::CreditAvailability.mark_unavailable!(resets_at: result.payload["resets_at"])
          true
        end

        def render_unavailable
          render json: { chat_unavailable: true }
        end
      end
    end
  end
end

# frozen_string_literal: true

require "securerandom"

module MosaicRelay
  module Admin
    class RelaySettingsController < ::Admin::AdminController
      # Engine isolation hides the host application's unqualified route
      # helpers from the host admin layout. Expose them to that layout while
      # retaining `main_app` for links owned by this engine.
      helper Rails.application.routes.url_helpers

      before_action :require_relay_administrator!
      helper_method :relay_documents_endpoint

      def edit
        @relay_setting = RelaySetting.current
        @source_statuses = SourceRegistry.source_statuses(host: request.host_with_port, protocol: request.protocol)
        @generated_source_token = session.delete(:mosaic_relay_generated_source_token)
      end

      def update
        @relay_setting = RelaySetting.current
        previous_source_types = @relay_setting.source_types
        previous_field_mappings = @relay_setting.source_field_mappings

        if @relay_setting.update(relay_setting_params)
          SourceSelectionSynchronizer.call(
            previous_source_types: previous_source_types,
            previous_field_mappings: previous_field_mappings,
            relay_setting: @relay_setting
          )
          redirect_to main_app.mosaic_relay_settings_path, notice: "Relay settings were saved."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def generate_bearer_token
        token = SecureRandom.urlsafe_base64(32)
        RelaySetting.current.update!(source_token: token)
        session[:mosaic_relay_generated_source_token] = token

        redirect_to main_app.mosaic_relay_settings_path(anchor: "relay-generated-token-panel"),
                    notice: "A new bearer access token was generated. Copy it now; it will not be shown again."
      end

      private

      def relay_documents_endpoint
        "#{request.base_url}#{MigrationContract::DOCUMENTS_ENDPOINT_PATH}"
      end

      def relay_setting_params
        attributes = params.require(:relay_setting).permit(
          :widget_markup, :public_base_url, :default_language, :page_size,
          source_types: [], source_field_mappings: {}
        )
        allowed_source_types = SourceRegistry.options(host: request.host_with_port, protocol: request.protocol).map(&:key)
        attributes[:source_types] = Array(attributes[:source_types]).map(&:to_s) & allowed_source_types
        attributes[:source_field_mappings] = attributes[:source_field_mappings].to_h.slice(*attributes[:source_types])
        attributes
      end

      def require_relay_administrator!
        return if current_admin_user&.admin?

        redirect_to main_app.admin_root_path, alert: "Only administrators can manage Relay settings."
      end
    end
  end
end

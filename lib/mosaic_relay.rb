require "mosaic_relay/version"
require "mosaic_relay/migration_contract"
require "mosaic_relay/legacy_pod_migrator"
require "mosaic_relay/source_registry"
require "mosaic_relay/configuration"
require "mosaic_relay/document_contract"
require "mosaic_relay/pod_definition"
require "mosaic_relay/pod_installer"
require "mosaic_relay/widget_markup"
require "mosaic_relay/model_hooks"
require "mosaic_relay/engine"

module MosaicRelay
  class << self
    def configuration
      configuration = Configuration.from_settings
      adapter_configuration = @adapter_configuration
      return configuration unless adapter_configuration

      Configuration::ADAPTER_ATTRIBUTES.each do |attribute|
        configuration.public_send("#{attribute}=", adapter_configuration.public_send(attribute))
      end
      configuration
    end

    def configure
      @adapter_configuration ||= Configuration.new
      yield(@adapter_configuration)
    end

    def adapter_configuration
      @adapter_configuration
    end

    def register_source(attributes)
      SourceRegistry.register(attributes)
    end

    def reset_configuration!
      @adapter_configuration = nil
    end
  end
end

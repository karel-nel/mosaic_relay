require "mosaic_relay/version"
require "mosaic_relay/configuration"
require "mosaic_relay/document_contract"
require "mosaic_relay/pod_definition"
require "mosaic_relay/pod_installer"
require "mosaic_relay/model_hooks"
require "mosaic_relay/engine"

module MosaicRelay
  class << self
    def configuration
      @configuration ||= Configuration.from_env
    end

    def configure
      yield(configuration)
    end

    def configure_from_env!(env = ENV)
      @configuration = Configuration.from_env(env)
    end

    def reset_configuration!
      @configuration = Configuration.from_env
    end
  end
end

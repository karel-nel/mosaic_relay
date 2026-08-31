# frozen_string_literal: true

require "yaml"

module MosaicRelay
  module PodDefinition
    PATH = File.expand_path("../../config/mosaic_relay/pod_definitions.yml", __dir__).freeze

    module_function

    def path
      PATH
    end

    def definitions
      YAML.safe_load_file(PATH, permitted_classes: [], permitted_symbols: [], aliases: false)
    end

    def relay_chat
      definitions.fetch("pod_definitions").fetch(MigrationContract::CANONICAL_POD_TYPE)
    end
  end
end

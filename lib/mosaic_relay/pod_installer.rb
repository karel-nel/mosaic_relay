# frozen_string_literal: true

module MosaicRelay
  class PodInstaller
    Result = Data.define(:status, :message, :record)

    def self.call(model: default_model)
      return yaml_only_result unless model

      definition = MosaicRelay::PodDefinition.relay_chat
      record = model.find_or_initialize_by(pod_type: MigrationContract::CANONICAL_POD_TYPE)
      record.assign_attributes(supported_attributes(record, definition))
      record.save!
      reload_schema_registry

      Result.new(
        status: :installed,
        message: "Installed Mosaic Relay Pod definition: #{MigrationContract::CANONICAL_POD_TYPE}",
        record:
      )
    end

    def self.default_model
      Object.const_get(:PodDefinition) if Object.const_defined?(:PodDefinition)
    end

    def self.yaml_only_result
      Result.new(
        status: :yaml_only,
        message: "No PodDefinition model is available; config/pod_definitions.yml remains the installed source.",
        record: nil
      )
    end

    def self.supported_attributes(record, definition)
      metadata = {
        "usable_in_sections" => definition.fetch("usable_in_sections", true),
        "complexity" => definition.fetch("complexity", "simple"),
        "recommended_for" => Array(definition["recommended_for"])
      }
      attributes = {
        name: definition["name"],
        description: definition["description"],
        category: definition["category"],
        icon: definition["icon"],
        schema: definition.fetch("schema", {}),
        metadata:,
        active: true
      }

      attributes.select { |name, _| record.respond_to?("#{name}=") }
    end

    def self.reload_schema_registry
      return unless defined?(::Admin::PodSchemas) && ::Admin::PodSchemas.respond_to?(:reload!)

      ::Admin::PodSchemas.reload!
    end

    private_class_method :default_model, :yaml_only_result, :supported_attributes, :reload_schema_registry
  end
end

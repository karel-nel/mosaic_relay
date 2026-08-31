# frozen_string_literal: true

module MosaicRelay
  # Explicit upgrade support for installations that used MosaicRelay's former
  # LLM Chat Window Pod. The task is deliberately opt-in: it reports first and
  # changes only records whose Pod type is the known legacy identifier.
  class LegacyPodMigrator
    LEGACY_HOST_FILES = %w[
      app/views/pods/shared/_llm_chat_window.html.erb
      app/views/pods/shared/_llm_chat_footer.html.erb
      app/javascript/controllers/mosaic_relay_llm_chat_controller.js
      app/javascript/controllers/llm_chat_controller.js
      app/assets/stylesheets/mosaic_relay/llm_chat.css
    ].freeze

    ModelResult = Data.define(:model_name, :legacy_count, :migrated_count, :error)
    Report = Data.define(:models, :host_files)

    class << self
      def report(models: default_models, root: Rails.root)
        Report.new(
          models: models.filter_map { |model| model_report(model) },
          host_files: LEGACY_HOST_FILES.select { |path| root.join(path).exist? }
        )
      end

      def migrate!(models: default_models)
        models.filter_map { |model| migrate_model(model) }
      end

      private

      def default_models
        %w[Pod PodDefinition].filter_map { |name| name.safe_constantize }.select { |model| pod_type_model?(model) }
      end

      def pod_type_model?(model)
        model.respond_to?(:where) && model.respond_to?(:column_names) && model.column_names.include?("pod_type")
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
        false
      end

      def model_report(model)
        return unless pod_type_model?(model)

        ModelResult.new(model.name, legacy_scope(model).count, 0, nil)
      rescue StandardError => error
        ModelResult.new(model.name, 0, 0, error.class.name)
      end

      def migrate_model(model)
        return unless pod_type_model?(model)

        legacy_records = legacy_scope(model)
        legacy_count = legacy_records.count
        migrated_count = legacy_records.update_all(pod_type: MigrationContract::CANONICAL_POD_TYPE)
        ModelResult.new(model.name, legacy_count, migrated_count, nil)
      rescue StandardError => error
        ModelResult.new(model.name, 0, 0, error.class.name)
      end

      def legacy_scope(model)
        model.where(pod_type: MigrationContract::LEGACY_POD_TYPES)
      end
    end
  end
end

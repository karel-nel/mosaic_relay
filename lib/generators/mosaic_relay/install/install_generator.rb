# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "pathname"
require "yaml"

module MosaicRelay
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      source_paths << MosaicRelay::Engine.root.to_s

      def self.exit_on_failure?
        true
      end

      def self.next_migration_number(dirname)
        timestamped_migrations = if ActiveRecord.respond_to?(:timestamped_migrations)
          ActiveRecord.timestamped_migrations
        elsif ActiveRecord::Base.respond_to?(:timestamped_migrations)
          ActiveRecord::Base.timestamped_migrations
        else
          true
        end

        if timestamped_migrations
          Time.current.utc.strftime("%Y%m%d%H%M%S")
        else
          format("%03d", current_migration_number(dirname) + 1)
        end
      end

      def ensure_host_application
        return unless Pathname.new(destination_root).expand_path == MosaicRelay::Engine.root.expand_path

        raise Thor::Error,
          "Run mosaic_relay:install from the consuming Mosaic application, not from the mosaic_relay gem directory."
      end

      def create_initializer
        template "initializer.rb", "config/initializers/mosaic_relay.rb"
      end

      def mount_engine
        routes_path = destination_path("config/routes.rb")
        mount = 'mount MosaicRelay::Engine => "/mosaic_relay"'

        unless File.exist?(routes_path)
          say_status :warning, "config/routes.rb not found; mount #{mount} manually"
          return
        end

        routes = File.read(routes_path)
        if routes.include?(mount)
          say_status :identical, "config/routes.rb"
        elsif (catch_all = routes.match(catch_all_route_pattern))
          insert_into_file routes_path, "#{catch_all[1]}#{mount}\n", before: catch_all_route_pattern
        else
          route mount
        end
      end

      def install_change_ledger_migration
        migration_name = "create_mosaic_relay_document_changes"
        migrations_path = destination_path("db/migrate")

        if self.class.migration_exists?(migrations_path, migration_name)
          say_status :identical, "db/migrate/#{migration_name}.rb"
        else
          migration_template(
            "db/migrate/20260821120000_create_mosaic_relay_document_changes.rb",
            "db/migrate/#{migration_name}.rb"
          )
        end
      end

      def install_stimulus_controller
        copy_file_unless_present(
          "app/javascript/controllers/llm_chat_controller.js",
          "app/javascript/controllers/mosaic_relay_llm_chat_controller.js"
        )

        index_path = "app/javascript/controllers/index.js"
        registration = <<~JAVASCRIPT

          import MosaicRelayLlmChatController from "./mosaic_relay_llm_chat_controller"
          application.register("llm-chat", MosaicRelayLlmChatController)
        JAVASCRIPT

        if !File.exist?(destination_path(index_path))
          say_status :warning, "#{index_path} not found; register mosaic_relay_llm_chat_controller.js manually"
        elsif File.read(destination_path(index_path)).include?('application.register("llm-chat"')
          say_status :identical, index_path
        else
          append_to_file index_path, registration
        end
      end

      def install_pod_views
        %w[
          app/views/pods/shared/_llm_chat_window.html.erb
          app/views/pods/shared/_llm_chat_footer.html.erb
        ].each { |path| copy_file_unless_present(path, path) }
      end

      def install_chat_styles
        stylesheet = "app/assets/stylesheets/mosaic_relay/llm_chat.css"
        copy_file_unless_present(stylesheet, stylesheet)

        application_stylesheet = "app/assets/stylesheets/application.tailwind.css"
        import = '@import "./mosaic_relay/llm_chat.css";'

        if !File.exist?(destination_path(application_stylesheet))
          say_status :warning, "#{application_stylesheet} not found; include #{stylesheet} manually"
        elsif File.read(destination_path(application_stylesheet)).include?(import)
          say_status :identical, application_stylesheet
        else
          prepend_to_file application_stylesheet, "#{import}\n"
        end
      end

      def install_pod_definition
        path = "config/pod_definitions.yml"
        destination = destination_path(path)

        unless File.exist?(destination)
          create_file path, YAML.dump("pod_definitions" => { "llm_chat_window" => MosaicRelay::PodDefinition.llm_chat_window })
          return
        end

        content = File.read(destination)
        if content.match?(/^\s{2}llm_chat_window:\s*$/)
          say_status :identical, path
          return
        end

        root = content.match(/^(?:pod_definitions|pods):[ \t]*\n/)&.to_s
        unless root
          say_status :warning, "#{path} has no pod_definitions root; add MosaicRelay::PodDefinition.llm_chat_window manually"
          return
        end

        inject_into_file path, pod_definition_yaml, after: root
      end

      def show_post_install_steps
        readme "POST_INSTALL"
      end

      private

      def destination_path(path)
        File.expand_path(path, destination_root)
      end

      def copy_file_unless_present(source, destination)
        if File.exist?(destination_path(destination))
          say_status :skip, "#{destination} already exists (host override preserved)"
        else
          copy_file source, destination
        end
      end

      def catch_all_route_pattern
        /^(\s*)(?:get|match)\s+["']\*path["']/
      end

      def pod_definition_yaml
        yaml = YAML.dump("llm_chat_window" => MosaicRelay::PodDefinition.llm_chat_window).delete_prefix("---\n")
        yaml.lines.map { |line| "  #{line}" }.join
      end
    end
  end
end

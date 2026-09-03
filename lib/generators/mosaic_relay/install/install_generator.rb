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
          timestamp = Time.current.utc.strftime("%Y%m%d%H%M%S").to_i
          next_number = current_migration_number(dirname).to_i + 1

          format("%014d", [ timestamp, next_number ].max)
        else
          format("%03d", current_migration_number(dirname) + 1)
        end
      end

      def ensure_host_application
        if Pathname.new(destination_root).expand_path == MosaicRelay::Engine.root.expand_path
          raise Thor::Error,
            "Run mosaic_relay:install from the consuming Mosaic application, not from the mosaic_relay gem directory."
        end

        required_files = %w[Gemfile config/application.rb config/routes.rb]
        missing_files = required_files.reject { |path| File.file?(destination_path(path)) }
        return if missing_files.empty?

        raise Thor::Error,
          "MosaicRelay requires a Rails application root; missing #{missing_files.join(', ')}."
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

      def install_relay_settings_migration
        migration_name = "create_mosaic_relay_settings"
        migrations_path = destination_path("db/migrate")

        if self.class.migration_exists?(migrations_path, migration_name)
          say_status :identical, "db/migrate/#{migration_name}.rb"
        else
          migration_template(
            "db/migrate/20260827000001_create_mosaic_relay_settings.rb",
            "db/migrate/#{migration_name}.rb"
          )
        end
      end

      def install_source_selection_migration
        migration_name = "add_source_selection_to_mosaic_relay_settings"
        migrations_path = destination_path("db/migrate")

        if self.class.migration_exists?(migrations_path, migration_name)
          say_status :identical, "db/migrate/#{migration_name}.rb"
        else
          migration_template(
            "db/migrate/20260831000001_add_source_selection_to_mosaic_relay_settings.rb",
            "db/migrate/#{migration_name}.rb"
          )
        end
      end

      def install_document_change_deletion_migration
        migration_name = "add_deleted_to_mosaic_relay_document_changes"
        migrations_path = destination_path("db/migrate")

        if self.class.migration_exists?(migrations_path, migration_name)
          say_status :identical, "db/migrate/#{migration_name}.rb"
        else
          migration_template(
            "db/migrate/20260831000002_add_deleted_to_mosaic_relay_document_changes.rb",
            "db/migrate/#{migration_name}.rb"
          )
        end
      end

      def install_relay_chat_view
        copy_file_unless_present(
          "app/views/pods/shared/_relay_chat.html.erb",
          "app/views/pods/shared/_relay_chat.html.erb"
        )
      end

      def install_relay_chat_pod_definition
        path = "config/pod_definitions.yml"
        destination = destination_path(path)

        unless File.exist?(destination)
          create_file path, YAML.dump("pod_definitions" => { "relay_chat" => MosaicRelay::PodDefinition.relay_chat })
          return
        end

        content = File.read(destination)
        if content.match?(/^\s{2}relay_chat:\s*$/)
          say_status :identical, path
          return
        end

        root = content.match(/^(?:pod_definitions|pods):[ \t]*\n/)&.to_s
        unless root
          say_status :warning, "#{path} has no pod_definitions root; add MosaicRelay::PodDefinition.relay_chat manually"
          return
        end

        inject_into_file path, pod_definition_yaml, after: root
      end

      def install_admin_sidebar_links
        sidebar_paths = [
          "app/views/layouts/admin/shared/_desktop_sidebar_content.erb",
          "app/views/layouts/admin/shared/_mobile_sidebar_content.html.erb"
        ]

        sidebar_paths.each do |path|
          destination = destination_path(path)
          next unless File.exist?(destination)

          content = File.read(destination)
          if content.include?("mosaic_relay_settings_path")
            say_status :identical, path
          elsif content.include?("</nav>")
            insert_admin_sidebar_link(destination, content)
          else
            say_status :warning, "#{path} has no navigation container; add Relay Settings manually"
          end
        end
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
        yaml = YAML.dump("relay_chat" => MosaicRelay::PodDefinition.relay_chat).delete_prefix("---\n")
        yaml.lines.map { |line| "  #{line}" }.join
      end

      def admin_sidebar_link
        <<~ERB

              <%= render partial: 'layouts/admin/shared/nav_item', locals: {
                name: "Relay Settings",
                path: mosaic_relay_settings_path,
                icon: "settings",
                current: controller_name == "relay_settings"
              } %>
        ERB
      end

      def insert_admin_sidebar_link(destination, content)
        # Keep Relay Settings next to the host's global settings entry when the
        # host provides one; otherwise retain the safe append-to-nav behavior.
        global_item = content.match(
          /^[ \t]*<%= render partial: ['"]layouts\/admin\/shared\/nav_item['"], locals: \{\s*\n[ \t]*name: ['"]Global['"]/
        )

        if global_item
          insert_into_file destination, admin_sidebar_link, before: global_item[0]
        else
          insert_into_file destination, admin_sidebar_link, before: "</nav>"
        end
      end
    end
  end
end

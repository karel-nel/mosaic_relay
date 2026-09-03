# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/mosaic_relay/install/install_generator"

class MosaicRelayInstallGeneratorTest < Rails::Generators::TestCase
  tests MosaicRelay::Generators::InstallGenerator
  destination MosaicRelay::Engine.root.join("tmp/install_generator_test")

  setup do
    prepare_destination
    write_host_file("Gemfile", "source \"https://rubygems.org\"\n")
    write_host_file("config/application.rb", "class Application < Rails::Application; end\n")
    write_host_file("config/routes.rb", "Rails.application.routes.draw do\nend\n")
  end

  test "installs the document feed and minimal Relay widget mount" do
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_includes content, 'mount MosaicRelay::Engine => "/mosaic_relay"'
    end

    assert_migration "db/migrate/create_mosaic_relay_document_changes.rb" do |content|
      assert_includes content, "create_table :mosaic_relay_document_changes"
    end

    assert_migration "db/migrate/create_mosaic_relay_settings.rb" do |content|
      assert_includes content, "create_table :mosaic_relay_settings"
    end

    assert_migration "db/migrate/add_source_selection_to_mosaic_relay_settings.rb" do |content|
      assert_includes content, "source_field_mappings"
    end

    assert_migration "db/migrate/add_deleted_to_mosaic_relay_document_changes.rb" do |content|
      assert_includes content, "add_column :mosaic_relay_document_changes, :deleted"
    end

    assert_file "app/views/pods/shared/_relay_chat.html.erb"
    assert_file "config/pod_definitions.yml" do |content|
      definitions = YAML.safe_load(content)
      assert definitions.fetch("pod_definitions").key?("relay_chat")
    end

    refute File.exist?(File.join(destination_root, "config/initializers/mosaic_relay.rb"))
    refute File.exist?(File.join(destination_root, "app/javascript/controllers/mosaic_relay_llm_chat_controller.js"))
    refute File.exist?(File.join(destination_root, "app/views/pods/shared/_llm_chat_window.html.erb"))
    refute File.exist?(File.join(destination_root, "app/assets/stylesheets/mosaic_relay/llm_chat.css"))
  end

  test "assigns unique migration versions when installation runs within one second" do
    stub_class_method(Time, :current, -> { Time.utc(2026, 8, 31, 12) }) { run_generator }

    versions = Dir.glob(File.join(destination_root, "db/migrate/*.rb")).sort.map do |path|
      File.basename(path).split("_", 2).first
    end

    assert_equal %w[20260831120000 20260831120001 20260831120002 20260831120003], versions
    assert_equal versions.length, versions.uniq.length
  end

  test "can be run twice without duplicate routes, migrations, or Pod definitions" do
    run_generator
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan('mount MosaicRelay::Engine => "/mosaic_relay"').length
    end

    migrations = Dir.glob(File.join(destination_root, "db/migrate/*_create_mosaic_relay_document_changes.rb"))
    assert_equal 1, migrations.length

    settings_migrations = Dir.glob(File.join(destination_root, "db/migrate/*_create_mosaic_relay_settings.rb"))
    assert_equal 1, settings_migrations.length

    source_migrations = Dir.glob(File.join(destination_root, "db/migrate/*_add_source_selection_to_mosaic_relay_settings.rb"))
    assert_equal 1, source_migrations.length

    deletion_migrations = Dir.glob(File.join(destination_root, "db/migrate/*_add_deleted_to_mosaic_relay_document_changes.rb"))
    assert_equal 1, deletion_migrations.length

    assert_file "config/pod_definitions.yml" do |content|
      assert_equal 1, content.scan(/^  relay_chat:/).length
    end
  end

  test "mounts before a conventional CMS catch-all route" do
    write_host_file(
      "config/routes.rb",
      <<~RUBY
        Rails.application.routes.draw do
          root "pages#home"
          get "*path", to: "pages#show"
        end
      RUBY
    )

    run_generator

    assert_file "config/routes.rb" do |content|
      assert_operator content.index('mount MosaicRelay::Engine => "/mosaic_relay"'), :<, content.index('get "*path"')
    end
  end

  test "adds an idempotent Relay Settings item to standard admin sidebars" do
    write_host_file(
      "app/views/layouts/admin/shared/_desktop_sidebar_content.erb",
      "<nav>\n  existing links\n</nav>\n"
    )
    write_host_file(
      "app/views/layouts/admin/shared/_mobile_sidebar_content.html.erb",
      "<nav>\n  existing links\n</nav>\n"
    )

    run_generator
    run_generator

    [
      "app/views/layouts/admin/shared/_desktop_sidebar_content.erb",
      "app/views/layouts/admin/shared/_mobile_sidebar_content.html.erb"
    ].each do |path|
      assert_file path do |content|
        assert_equal 1, content.scan("mosaic_relay_settings_path").length
        assert_includes content, 'name: "Relay Settings"'
      end
    end
  end

  test "places Relay Settings immediately before a Global sidebar item" do
    sidebar = <<~ERB
      <nav>
        <%= render partial: 'layouts/admin/shared/nav_item', locals: {
          name: "Global",
          path: admin_settings_path,
          icon: "settings",
          current: controller_name == "settings"
        } %>
      </nav>
    ERB
    write_host_file("app/views/layouts/admin/shared/_desktop_sidebar_content.erb", sidebar)

    run_generator

    assert_file "app/views/layouts/admin/shared/_desktop_sidebar_content.erb" do |content|
      assert_operator content.index('name: "Relay Settings"'), :<, content.index('name: "Global"')
    end
  end

  test "refuses to install into the gem source directory" do
    routes_before = File.read(MosaicRelay::Engine.root.join("config/routes.rb"))
    install_generator = MosaicRelay::Generators::InstallGenerator.new(
      [], {}, destination_root: MosaicRelay::Engine.root.to_s
    )

    error = assert_raises(Thor::Error) { install_generator.ensure_host_application }

    assert_includes error.message, "consuming Mosaic application"
    assert_equal routes_before, File.read(MosaicRelay::Engine.root.join("config/routes.rb"))
  end

  test "refuses to install outside a Rails application root" do
    FileUtils.rm_f(File.join(destination_root, "Gemfile"))
    FileUtils.rm_f(File.join(destination_root, "config/application.rb"))

    install_generator = MosaicRelay::Generators::InstallGenerator.new(
      [], {}, destination_root: destination_root
    )
    error = assert_raises(Thor::Error) { install_generator.ensure_host_application }

    assert_includes error.message, "Rails application root"
  end

  private

  def write_host_file(path, content)
    absolute_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end
end

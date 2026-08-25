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
    write_host_file(
      "app/javascript/controllers/index.js",
      "import { application } from \"./application\"\n"
    )
    write_host_file(
      "app/assets/stylesheets/application.tailwind.css",
      "@import \"tailwindcss\";\n"
    )
    write_host_file(
      "config/pod_definitions.yml",
      "---\npod_definitions:\n  rich_text_block:\n    name: Rich Text Block\n"
    )
  end

  test "installs the Mosaic Relay host integration" do
    run_generator

    assert_file "config/initializers/mosaic_relay.rb" do |content|
      assert_includes content, "MosaicRelay.configure"
      assert_not_includes content, "RELAY_CHAT_TOKEN ="
      assert_includes content, "RELAY_REDIS_URL"
    end

    assert_file "config/routes.rb" do |content|
      assert_includes content, 'mount MosaicRelay::Engine => "/mosaic_relay"'
    end

    assert_migration "db/migrate/create_mosaic_relay_document_changes.rb" do |content|
      assert_includes content, "create_table :mosaic_relay_document_changes"
    end

    assert_file "app/javascript/controllers/mosaic_relay_llm_chat_controller.js"
    assert_file "app/javascript/controllers/index.js" do |content|
      assert_includes content, 'application.register("llm-chat", MosaicRelayLlmChatController)'
    end

    assert_file "app/views/pods/shared/_llm_chat_window.html.erb"
    assert_file "app/views/pods/shared/_llm_chat_footer.html.erb"
    assert_file "app/assets/stylesheets/mosaic_relay/llm_chat.css"
    assert_file "app/assets/stylesheets/application.tailwind.css" do |content|
      assert content.start_with?('@import "./mosaic_relay/llm_chat.css";')
    end

    assert_file "config/pod_definitions.yml" do |content|
      definitions = YAML.safe_load(content)
      assert definitions.fetch("pod_definitions").key?("rich_text_block")
      assert definitions.fetch("pod_definitions").key?("llm_chat_window")
    end
  end

  test "can be run twice without duplicate registrations" do
    run_generator
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan('mount MosaicRelay::Engine => "/mosaic_relay"').length
    end

    assert_file "app/javascript/controllers/index.js" do |content|
      assert_equal 1, content.scan('application.register("llm-chat"').length
    end

    assert_file "config/pod_definitions.yml" do |content|
      assert_equal 1, content.scan(/^  llm_chat_window:/).length
    end

    migrations = Dir.glob(File.join(destination_root, "db/migrate/*_create_mosaic_relay_document_changes.rb"))
    assert_equal 1, migrations.length
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

  test "refuses to install into the gem source directory" do
    routes_before = File.read(MosaicRelay::Engine.root.join("config/routes.rb"))
    install_generator = MosaicRelay::Generators::InstallGenerator.new(
      [],
      {},
      destination_root: MosaicRelay::Engine.root.to_s
    )

    error = assert_raises(Thor::Error) { install_generator.ensure_host_application }

    assert_includes error.message, "consuming Mosaic application"
    assert_equal routes_before, File.read(MosaicRelay::Engine.root.join("config/routes.rb"))
    assert_not File.exist?(MosaicRelay::Engine.root.join("config/initializers/mosaic_relay.rb"))
  end

  test "refuses to install outside a Rails application root" do
    write_host_file("config/routes.rb", "Rails.application.routes.draw do\nend\n")
    FileUtils.rm_f(File.join(destination_root, "Gemfile"))
    FileUtils.rm_f(File.join(destination_root, "config/application.rb"))

    install_generator = MosaicRelay::Generators::InstallGenerator.new(
      [],
      {},
      destination_root: destination_root
    )
    error = assert_raises(Thor::Error) { install_generator.ensure_host_application }

    assert_includes error.message, "Rails application root"
    assert_not File.exist?(File.join(destination_root, "config/initializers/mosaic_relay.rb"))
  end

  test "preserves an existing initializer" do
    write_host_file("config/initializers/mosaic_relay.rb", "MosaicRelay.configure { |config| config.chat_tenant_key = \"custom\" }\n")

    run_generator

    assert_file "config/initializers/mosaic_relay.rb" do |content|
      assert_includes content, 'config.chat_tenant_key = "custom"'
      assert_not_includes content, "RELAY_REDIS_URL"
    end
  end

  private

  def write_host_file(path, content)
    absolute_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end
end

# frozen_string_literal: true

require "test_helper"

class MosaicRelayLegacyPodMigratorTest < ActiveSupport::TestCase
  Scope = Struct.new(:records) do
    def count
      records.length
    end

    def update_all(pod_type:)
      records.each { |record| record.pod_type = pod_type }
      records.length
    end
  end

  Record = Struct.new(:pod_type)

  Model = Class.new do
    class << self
      attr_accessor :records

      def name
        "Pod"
      end

      def column_names
        [ "pod_type" ]
      end

      def where(pod_type:)
        Scope.new(records.select { |record| Array(pod_type).include?(record.pod_type) })
      end
    end
  end

  test "reports legacy Pod records and host files without changing them" do
    Model.records = [ Record.new("llm_chat_window"), Record.new("relay_chat") ]
    root = Pathname.new(Dir.mktmpdir)
    legacy_view = root.join("app/views/pods/shared/_llm_chat_window.html.erb")
    FileUtils.mkdir_p(legacy_view.dirname)
    FileUtils.touch(legacy_view)

    report = MosaicRelay::LegacyPodMigrator.report(models: [ Model ], root: root)

    assert_equal 1, report.models.sole.legacy_count
    assert_equal [ "app/views/pods/shared/_llm_chat_window.html.erb" ], report.host_files
    assert_equal "llm_chat_window", Model.records.first.pod_type
  ensure
    FileUtils.remove_entry(root) if root&.exist?
  end

  test "migrates only legacy Pod records to relay_chat" do
    Model.records = [ Record.new("llm_chat_window"), Record.new("relay_chat") ]

    result = MosaicRelay::LegacyPodMigrator.migrate!(models: [ Model ]).sole

    assert_equal 1, result.legacy_count
    assert_equal 1, result.migrated_count
    assert_equal [ "relay_chat", "relay_chat" ], Model.records.map(&:pod_type)
  end
end

namespace :mosaic_relay do
  namespace :install do
    desc "Install or update the Relay Chat Pod definition"
    task pod_definition: :environment do
      puts MosaicRelay::PodInstaller.call.message
    end
  end

  namespace :upgrade do
    desc "Report legacy Relay Chat Pod records and host-generated files without changing them"
    task report: :environment do
      report = MosaicRelay::LegacyPodMigrator.report
      report.models.each do |result|
        puts "#{result.model_name}: #{result.legacy_count} legacy Pod record(s)"
      end
      puts "No legacy Pod models found." if report.models.empty?
      if report.host_files.any?
        puts "Host files to remove or replace manually:"
        report.host_files.each { |path| puts "  #{path}" }
      else
        puts "No known legacy host-generated files found."
      end
    end

    desc "Migrate llm_chat_window Pod records to relay_chat"
    task migrate_legacy_pods: :environment do
      results = MosaicRelay::LegacyPodMigrator.migrate!
      results.each do |result|
        if result.error
          warn "#{result.model_name}: migration failed (#{result.error})"
        else
          puts "#{result.model_name}: migrated #{result.migrated_count} of #{result.legacy_count} legacy Pod record(s)"
        end
      end
      puts "No legacy Pod models found." if results.empty?
    end
  end
end

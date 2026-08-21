namespace :mosaic_relay do
  namespace :install do
    desc "Install or update the LLM Chat Window Pod definition"
    task pod_definition: :environment do
      puts MosaicRelay::PodInstaller.call.message
    end
  end
end

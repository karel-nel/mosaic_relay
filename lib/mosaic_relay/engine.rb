module MosaicRelay
  class Engine < ::Rails::Engine
    isolate_namespace MosaicRelay

    config.to_prepare do
      MosaicRelay::ModelHooks.install!
    end
  end
end

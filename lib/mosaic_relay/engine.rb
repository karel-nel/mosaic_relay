module MosaicRelay
  class Engine < ::Rails::Engine
    isolate_namespace MosaicRelay

    initializer "mosaic_relay.admin_routes" do |app|
      app.routes.prepend do
        get "/admin/relay_settings", to: "mosaic_relay/admin/relay_settings#edit", as: :mosaic_relay_settings
        patch "/admin/relay_settings", to: "mosaic_relay/admin/relay_settings#update"
        post "/admin/relay_settings/generate_bearer_token",
             to: "mosaic_relay/admin/relay_settings#generate_bearer_token",
             as: :mosaic_relay_generate_bearer_token
      end
    end

    config.to_prepare do
      MosaicRelay::ModelHooks.install!
    end
  end
end

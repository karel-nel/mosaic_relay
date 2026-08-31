MosaicRelay::Engine.routes.draw do
  namespace :api do
    namespace :relay do
      get "documents", to: "documents#index"
    end
  end
end

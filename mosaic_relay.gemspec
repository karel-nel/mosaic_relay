require_relative "lib/mosaic_relay/version"

Gem::Specification.new do |spec|
  spec.name        = "mosaic_relay"
  spec.version     = MosaicRelay::VERSION
  spec.authors     = [ "Jason-W-Cameron" ]
  spec.email       = [ "jason@niimble.io" ]
  spec.homepage    = "https://niimble.io"
  spec.summary     = "Mosaic integration for Niimble Relay."
  spec.description = "A Rails engine that integrates Mosaic CMS sites with Niimble Relay chat and document-ingestion APIs."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,docs,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0.3"
  spec.add_dependency "nokogiri", ">= 1.12"
  spec.add_dependency "redis", ">= 5.0"
end

require_relative "lib/mosaic_relay/version"

Gem::Specification.new do |spec|
  spec.name        = "mosaic_relay"
  spec.version     = MosaicRelay::VERSION
  spec.authors     = [ "Jason-W-Cameron" ]
  spec.email       = [ "jason@niimble.io" ]
  spec.homepage    = "https://niimble.io"
  spec.summary     = "Mosaic integration for Niimble Relay."
  spec.description = "A Rails engine that exposes Mosaic CMS content to Niimble Relay."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,docs,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.1", "< 8.2"
  spec.add_dependency "nokogiri", ">= 1.12"
end

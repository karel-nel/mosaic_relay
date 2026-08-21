# MosaicRelay

Mosaic integration for the Niimble Relay chat and document-ingestion APIs.

## Configuration

The gem reads its default configuration from environment variables. Credentials
must remain server-side and must never be embedded in the browser Pod.

```text
RELAY_SOURCE_TOKEN
RELAY_PUBLIC_BASE_URL
RELAY_CHAT_BASE_URL
RELAY_CHAT_TOKEN
RELAY_CHAT_TENANT_KEY
RELAY_CHAT_OPEN_TIMEOUT_SECONDS
RELAY_CHAT_READ_TIMEOUT_SECONDS
RELAY_DEFAULT_LANGUAGE
RELAY_DOCUMENTS_PAGE_SIZE
```

Applications can override the environment-derived values during initialization:

```ruby
MosaicRelay.configure do |config|
  config.chat_read_timeout_seconds = 60
end
```

The content extractors automatically use Mosaic's `Admin::PodSchemas` when it
is available. A host can provide an explicit schema resolver or asset URL
builder when its CMS uses different adapters:

```ruby
MosaicRelay.configure do |config|
  config.pod_schema_resolver = ->(pod_type) { MyPodSchemas.schema_for(pod_type) }
  config.asset_url_builder = ->(blob) { "https://cdn.example/#{blob.key}" }
  config.page_model = MyPage
  config.blog_model = MyBlog
  config.page_element_model = MyPageElement
end
```

When the configured Mosaic models are present, the engine automatically adds
change-ledger callbacks for pages, blogs, pods, page structure, and blog
taxonomy/association records.

Blogs with a future `published_at` are excluded from the initial feed. The
engine schedules `MosaicRelay::ScheduledBlogPublicationJob`, which records a
new change when the blog becomes displayable so the next incremental feed
request ingests it.

## Usage
The gem exposes the Relay chat integration and the canonical document
contract used by the Mosaic source feed. The document feed uses an append-only
change ledger in `mosaic_relay_document_changes`; run the engine migrations in
the host application before enabling ingestion. See
`docs/canonical_document_contract.md` for the feed shape and synchronization
rules.

## Installation
Add this line to your application's Gemfile:

```ruby
gem "mosaic_relay"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install mosaic_relay
```

Install the engine integration into the Mosaic application:

```bash
bin/rails generate mosaic_relay:install
bin/rails db:migrate
bin/rails mosaic_relay:install:pod_definition
```

The generator mounts the engine, installs the change-ledger migration and
initializer, registers the Stimulus controller, installs overridable Pod views
and styles, and merges the `llm_chat_window` definition into
`config/pod_definitions.yml`. Existing host overrides are preserved.

Run the generator from the consuming Mosaic application, not from this gem's
source directory. The Pod installation task updates the host's
`PodDefinition` record when that model is available and otherwise leaves the
installed YAML definition as the source of truth.

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

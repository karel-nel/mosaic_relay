# MosaicRelay

MosaicRelay exposes Mosaic CMS content to Niimble Relay through an
authenticated, cursor-based document feed. Relay owns the visitor-facing chat
experience; this gem does not ship browser chat UI, styles, JavaScript, Action
Cable, or a server-side chat proxy.

## Compatibility

MosaicRelay supports Ruby 3.2+ and Rails 7.1, 7.2, 8.0, and 8.1.

## Configuration

Relay integration settings are stored in the application's database, not in
environment variables. After installation and migration, sign in as a Mosaic
administrator and visit `/admin/relay_settings` to:

- generate the bearer token Relay uses to fetch documents;
- set the document language and page size; and
- choose which Mosaic content sources and safe text fields Relay may ingest; and
- paste Relay's public widget markup.

The generated bearer token is shown once. Store it in Relay's HTTP source
configuration with the document-feed endpoint below.

Mosaic-specific model and extraction adapters remain code configuration:

Applications can still configure Mosaic-specific model and extraction adapters:

```ruby
MosaicRelay.configure do |config|
  config.pod_schema_resolver = ->(pod_type) { MyPodSchemas.schema_for(pod_type) }
  config.asset_url_builder = ->(blob) { "https://cdn.example/#{blob.key}" }
  config.blog_path_builder = ->(blog) { "/articles/#{ERB::Util.url_encode(blog.slug)}" }
  config.page_path_builder = ->(page) { page.slug == "home" ? "/" : "/site/#{ERB::Util.url_encode(page.slug)}" }
  config.page_model = MyPage
  config.blog_model = MyBlog
  config.page_element_model = MyPageElement
end
```

For sites that expose content families beyond Pages and Blogs, a source provider
can return source contracts dynamically. The provider is evaluated whenever the
registry is read, so sources registered by host engines or initializers are
available to Relay Settings and the feed without a cached source list:

```ruby
MosaicRelay.configure do |config|
  config.source_provider = -> {
    [
      {
        key: "announcements",
        model: Announcement,
        title: :title,
        fields: %i[summary body],
        field_options: %i[summary body],
        scope: :published,
        collection_path: "/announcements",
        record_path: ->(record) { "/announcements/#{record.slug}" }
      }
    ]
  }
end
```

`MosaicRelay.register_source` remains available for one-off registrations. Built-in
Page and Blog paths use the host application's `page_path`/`blog_path` route
helpers when available; custom paths can always be supplied with the path
builders above. Both
APIs use the same explicit public URL, publication scope, and field allowlist
contract; neither exposes arbitrary application models automatically.

### Custom public sources

Pages and Blogs are registered automatically. A host can expose another
content family only with an explicit, public contract:

```ruby
MosaicRelay.register_source(
  key: "announcements",
  label: "Announcements",
  model: Announcement,
  title: :title,
  fields: %i[summary body],
  field_options: %i[summary body],
  scope: :published,
  collection_path: "/announcements",
  record_path: ->(announcement) { "/announcements/#{announcement.slug}" }
)
```

Relay Settings performs anonymous, in-process `GET` requests for each collection
URL and a representative public record URL. The source is selectable only when
its model, scope, public collection URL, and record URL are present and both
endpoints return successful public responses. A source with no public records is
shown as unavailable until there is a record to validate.
For incremental updates, add a normal host callback that calls
`MosaicRelay::ChangeRecorder.record_source("announcements", self)`.

The `relay_chat` Pod renders only Relay's public widget mount. The mount strips
inline script tags and loads Relay's public widget script once per page. Private
chat credentials must never be included in this markup. See [the migration
contract](docs/migration_contract.md).

## Installation

```bash
bin/rails generate mosaic_relay:install
bin/rails db:migrate
bin/rails mosaic_relay:install:pod_definition
```

The installer mounts the engine, installs the document-change ledger and Relay
Settings migrations, and adds the minimal `relay_chat` Pod view and definition.
It does not create a chat UI, browser controller, stylesheet, Action Cable
configuration, or server-side chat proxy.

Relay fetches content from:

```text
GET /mosaic_relay/api/relay/documents
```

The canonical public site URL is optional. The feed automatically derives an
absolute origin from the incoming request; set the override only when a proxy,
load balancer, or canonical-domain redirect means that request host is not the
public site visitors use.

## Upgrading from the legacy chat implementation

The gem no longer provides the `llm_chat_window` UI or `/api/relay/chat`
endpoints. The old installer copied templates, JavaScript, and styles into host
applications; those copies are intentionally not deleted automatically.

Before deploying, remove or replace any host copies of:

- `app/views/pods/shared/_llm_chat_window.html.erb`
- `app/views/pods/shared/_llm_chat_footer.html.erb`
- `app/javascript/controllers/mosaic_relay_llm_chat_controller.js`
- `app/assets/stylesheets/mosaic_relay/llm_chat.css`

The `relay_chat` Pod replaces these files without reintroducing a Mosaic-owned
chat UI.

Run the report before changing an existing installation:

```bash
bin/rails mosaic_relay:upgrade:report
```

After reviewing its output, migrate the known legacy Pod records explicitly:

```bash
bin/rails mosaic_relay:upgrade:migrate_legacy_pods
```

The report never deletes host files. Remove or replace any files it lists only
after confirming the Relay widget is configured.

## License

The gem is available under the [MIT License](MIT-LICENSE).

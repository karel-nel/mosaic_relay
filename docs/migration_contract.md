# Mosaic Relay migration contract

This document defines the values that must remain stable while `mosaic_relay`
is migrated to the Relay-owned widget and database-backed settings model.

## Contract version

The current contract is version `1`, represented by
`MosaicRelay::MigrationContract::VERSION`. A change to any externally visible
value below requires an explicit contract version and upgrade notes.

## Relay document feed

The authenticated document feed remains available at:

```text
GET /mosaic_relay/api/relay/documents
```

The endpoint continues to accept an opaque `cursor` and return the existing
document envelope. Authentication is read from the singleton Relay Settings
record; the endpoint path itself does not change.

## Stable document identity

Document IDs remain stable across the migration:

| Mosaic source | External ID format |
| --- | --- |
| Pages | `pages:<record-id>` |
| Blogs | `blogs:<record-id>` |

Relay uses these IDs for updates and deletions. Serializers, change callbacks,
cursors, source selection, and tombstones must all use the same format.

Active documents retain the current canonical document contract. Deletions
continue to use the minimal `{ "external_id": "...", "deleted": true }`
shape.

## Pod identity

`relay_chat` is the canonical Pod type. Existing `llm_chat_window` records are
legacy input. Run `bin/rails mosaic_relay:upgrade:report` first, then run
`bin/rails mosaic_relay:upgrade:migrate_legacy_pods` to update known `Pod` and
`PodDefinition` records that expose a `pod_type` column. The replacement Pod
renders only a Relay widget mount; chat conversation UI, styling, and browser
behavior belong to Relay.

## Configuration boundary

The configuration source is a database-backed Relay Settings record. Source
credentials, public document settings, and widget markup must not be supplied
through `RELAY_*` environment variables. The migration must not change document
IDs or feed URLs while source selection and field mappings are configured.

`public_base_url` is an optional canonical-origin override. When it is blank,
the document endpoint derives an absolute origin from the incoming request,
matching the Refinery Relay Rails 8 integration.

No private chat credential may be emitted into the widget markup or browser
JavaScript. The feed bearer token is generated and stored through the Relay
Settings screen, and displayed only once at generation time.

## Compatibility policy

- Preserve Rails 7.1, 7.2, 8.0, and 8.1 support.
- Preserve the existing Mosaic page/blog serializers and change ledger unless
  a contract-preserving adapter is required.
- Keep the current endpoint and external IDs for existing Relay sources.
- Run the upgrade diagnostic before removing generated host files; it never
  removes files automatically.
- Do not automatically delete host overrides or application data.

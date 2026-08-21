# Mosaic Relay document contract

The Mosaic Relay gem exposes an authenticated HTTP source feed for Niimble
Relay. Relay requests:

```http
GET /api/relay/documents?cursor=<opaque-cursor>
Authorization: Bearer <source-token>
Accept: application/json
```

Every successful response is a JSON object containing a `documents` array. A
response may also include `cursor` and `next_cursor`. Cursors are opaque to
Relay and must be replay-safe.

## Active document

An active document should use this canonical shape. The gem normalizes omitted
optional fields to their documented defaults:

```json
{
  "external_id": "pages:race-day",
  "title": "Race day information",
  "url": "https://client.example/race-day",
  "content": "Clean searchable text.",
  "content_type": "page",
  "language": "en",
  "updated_at": "2026-08-12T10:15:00Z",
  "content_hash": "a7d4f5087024f93c0b6efab3fd3f33f9d46544a3b84fa7dd9c380153d9a1f771",
  "deleted": false,
  "content_blocks": [],
  "metadata": {}
}
```

Required rules:

- `external_id` is stable and unique within the source.
- `url` is an absolute public HTTPS URL in production.
- `content` is cleaned, searchable plain text without shared navigation or
  footer chrome.
- `updated_at` is an ISO 8601 timestamp with timezone.
- `content_hash` is a lowercase 64-character SHA-256 digest of the canonical
  searchable representation.
- `deleted` defaults to `false`.
- `content_blocks` defaults to an empty ordered array.
- `metadata` defaults to an empty JSON object.

## Deletion record

Unpublished or removed content must be emitted explicitly:

```json
{
  "external_id": "pages:obsolete-race-info",
  "deleted": true
}
```

Relay must not infer deletion from a document being absent from a response.

## Pagination and synchronization

- The first request returns a bounded initial snapshot.
- Later requests return changes after the supplied cursor.
- `next_cursor` is present when another page must be fetched.
- The final page omits `next_cursor` or returns it as `null`.
- Changes include new, updated, unpublished, and deleted records.
- Replayed cursor requests must be safe and idempotent.

Scheduled blogs are not included until they are both visible and their
`published_at` time has arrived. The scheduled publication job records a new
blog change at that point so incremental consumers can ingest the document.

The full source-feed behavior is described in the Mosaic CMS reference
documentation at `docs/niimble_relay/canonical_document_contract.md`.

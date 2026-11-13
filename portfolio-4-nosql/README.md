# Portfolio 4 - NoSQL (MongoDB)

**Student:** Johnson Kazeem | **Matric:** 2026/A/MIT/0691 | **Database:** `txnbank` (MongoDB 7+)

## Overview

This portfolio implements the document store for Lagos Meridian Bank's audit and fraud-detection side of the system. The relational schema in Portfolio 1 remains the system of record for balances and transfers; MongoDB holds the high-volume, schema-flexible event log and the fraud case file.

Two collections are created:

- `transaction_events` - one document per audit event (initiated, settled, failed, reversed) with channel-specific metadata for branch, internet banking and USSD.
- `fraud_alerts` - fraud cases raised against transfers, with severity and status.

No card numbers, CVV or PIN values are stored in either collection.

## Files

| File | Purpose |
| --- | --- |
| `01_setup.js` | Creates the two collections with `$jsonSchema` validators. Uses `db = db.getSiblingDB("txnbank")`, `enum` (never `const`), `oneOf` (never `if/then/else`), and `additionalProperties: false` with every field (including `_id`) listed. |
| `02_data_and_queries.js` | Seeds 12 transaction events and 3 fraud alerts, then runs 3 aggregation pipelines: total value by channel, top 5 transfers by event count, and failed-rate by channel. |
| `03_bulk_and_index_demo.js` | Inserts 40,000 documents with `insertMany` in batches of 1,000, then compares a `COLLSCAN` (using `hint({$natural:1})`) against a compound `IXSCAN`, printing Stage / Docs / Time ms for both. |

## Running

```bash
mongosh txnbank portfolio-4-nosql/01_setup.js
mongosh txnbank portfolio-4-nosql/02_data_and_queries.js
mongosh txnbank portfolio-4-nosql/03_bulk_and_index_demo.js
```

## Schema design notes

### `transaction_events`

The document has a fixed set of top-level fields (`_id`, `event_id`, `transfer_reference`, `channel`, `event_type`, `amount`, `currency`, `metadata`, `created_at`). `additionalProperties: false` is set, so every field must be listed in `properties` (including `_id`).

The `metadata` sub-document is branched on `channel` using `oneOf`:

- `channel: "branch"` -> `metadata` must contain `teller_id` and `branch_code`.
- `channel: "internet_banking"` -> `metadata` must contain `session_id` and `ip_address`.
- `channel: "ussd"` -> `metadata` must contain `phone` and `ussd_code`.

Each branch's `metadata` schema also sets `additionalProperties: false` so a branch event cannot accidentally carry an `ip_address`.

`currency` is `enum: ["NGN"]` - one value, using `enum` instead of `const` per the portfolio rules.

### `fraud_alerts`

The document has severity, status, reason, amount, currency, created_at, and optional `reviewed_at` / `reviewer`. `oneOf` enforces that an `OPEN` alert has no reviewer, while `IN_REVIEW` or `CLOSED` alerts must have `reviewed_at` and `reviewer`.

## Number types

Per the portfolio rules, numbers inserted in `02_data_and_queries.js` and `03_bulk_and_index_demo.js` use `Double()` for amounts and `Int32()` for counts. The schema declares `amount` as `bsonType: "double"`.

## Bulk and index demo output

The demo prints a summary table after running both plans. Paste the real output below after running:

```
[paste real output here]
```

The expected shape is:

```
Stage     | Docs examined | Time ms
BEFORE    | 40000         | <larger>
AFTER     | <much smaller> | <smaller>
```

The `BEFORE` plan is a `COLLSCAN` (every document is scanned). The `AFTER` plan is an `IXSCAN` on `idx_channel_amount_created` that examines only the matching documents.

## dropIndex safety

`dropIndex` is wrapped in `try/catch` at the top of `03_bulk_and_index_demo.js` so the script is re-runnable even on a fresh database where the index does not exist yet.

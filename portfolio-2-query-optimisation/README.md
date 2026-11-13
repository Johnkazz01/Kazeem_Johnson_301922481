# Portfolio 2 - Query Optimisation

**Student:** Johnson Kazeem | **Matric:** 2026/A/MIT/0691 | **Database:** `txnbank`

## Overview

This portfolio contains 8 reporting queries against the Lagos Meridian Bank schema from Portfolio 1, and an EXPLAIN ANALYZE script that measures the effect of the supporting indexes on the four selective queries.

## Files

| File | Purpose |
| --- | --- |
| `01_queries.sql` | 8 queries: 4 selective (account statement, branch report, customer report, last 30 days) and 4 aggregates (daily value per branch, top customers by volume, failed-transfer rate, channel mix). |
| `02_explain_analyze.sql` | Drops the composite P2 indexes, runs `EXPLAIN (ANALYZE, BUFFERS)` on the 4 selective queries, recreates the indexes, runs them again, and finally shows that the aggregate query Q5 keeps a Seq Scan by design. |

## Running

```bash
psql -d txnbank -v ON_ERROR_STOP=1 -f 01_queries.sql
psql -d txnbank -v ON_ERROR_STOP=1 -f 02_explain_analyze.sql
```

## The 8 queries

| # | Type | Description |
| --- | --- | --- |
| 1 | Selective | Account statement - all ledger entries for one account in the last 60 days. |
| 2 | Selective | Branch report - all transfers whose debit account is held at a given branch in the last 30 days. |
| 3 | Selective | Customer report - all transfers where the customer is either the debit or credit account owner. |
| 4 | Selective | Last 30 days - every transfer created in the last 30 days with both account numbers. |
| 5 | Aggregate | Daily transaction value per branch (settled transfers only). |
| 6 | Aggregate | Top 10 customers by settled transfer volume. |
| 7 | Aggregate | Failed-transfer rate per day. |
| 8 | Aggregate | Channel mix - count and value per channel, with percentage of total transactions. |

## Indexes evaluated

The composite indexes that this portfolio adds on top of the FK indexes from Portfolio 1:

```sql
CREATE INDEX idx_ledger_account_date    ON ledger_entry(account_id, created_at);
CREATE INDEX idx_transfer_created_debit ON transfer(created_at, debit_account_id);
CREATE INDEX idx_transfer_created_at     ON transfer(created_at);
```

- `idx_ledger_account_date` backs the account statement (Q1), which filters by `account_id` and orders by `created_at`.
- `idx_transfer_created_at` backs the last-30-days report (Q4), which filters by `created_at` and orders by `created_at DESC`.
- `idx_transfer_created_debit` backs the branch report (Q2) via a filter on `created_at` plus a join on `debit_account_id`.

## EXPLAIN ANALYZE results

The four selective queries, before and after the supporting indexes, produce:

```
[paste real output here]
```

## Honesty note on aggregates

The aggregate queries (Q5-Q8) scan a large fraction of the `transfer` table (every settled transfer for the daily-value-per-branch report, every transfer for the failed-rate report). After recreating the supporting indexes the planner still chooses a Seq Scan + Hash Aggregate for these queries, because the index would not reduce the number of rows enough to justify the random IO of an Index Scan followed by a sort. This is the expected behaviour and is shown explicitly in PHASE 4 of `02_explain_analyze.sql`. We do not claim that every query gets faster after indexing.

The selective queries (Q1-Q4), by contrast, benefit from the indexes because they touch a small fraction of the table and the index lets the planner do an Index Scan that returns only the matching rows.

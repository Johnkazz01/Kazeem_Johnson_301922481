# Portfolio 5 - Distributed and Cloud

**Student:** Johnson Kazeem | **Matric:** 2026/A/MIT/0691 | **Database:** `txnbank`

## Overview

This portfolio addresses horizontal scaling of the biggest table and the cloud database design for Lagos Meridian Bank. The partitioning script demonstrates monthly RANGE partitioning with a DO loop and partition pruning. The design document describes a managed-database deployment with synchronous replication for the ledger and asynchronous replication for reporting, plus Nigerian data-residency notes.

## Files

| File | Purpose |
| --- | --- |
| `01_partitioning.sql` | Creates a partitioned copy of `ledger_entry` by `created_at`. A DO loop creates one partition per month covering every month in the data plus next month, plus a DEFAULT partition. Prints rows per partition and one pruned one-month EXPLAIN ANALYZE. |
| `cloud_design.md` | Managed-database design: multi-AZ synchronous primary, asynchronous read replica, MongoDB replica set, backups. Synchronous-vs-asynchronous trade-offs and why the ledger must be synchronous. Nigerian data-residency notes: NDPA 2023 and CBN supervisory expectations. |
| `README.md` | This file. |

## Running

```bash
psql -d txnbank -v ON_ERROR_STOP=1 -f 01_partitioning.sql
```

The script depends on Portfolio 1 (tables, seed and bulk data) being loaded first.

## Partitioning details

- Parent: `ledger_entry_part`, partitioned by RANGE on `created_at`.
- Primary key: `(ledger_id, created_at)` - includes the partition key as required by PG16.
- Partitions: one per month, named `ledger_entry_part_YYYY_MM`, created by a DO loop that walks from the first month present in the data through to next month relative to today.
- A DEFAULT partition (`ledger_entry_part_default`) catches any row that falls outside the explicit range.
- No EXCLUDE constraint is declared because PG16 does not allow exclusion constraints on a partitioned parent.

## Partition pruning output

After running, the script prints a row-count per partition and two EXPLAIN ANALYZE plans: one for the current month and one for the previous month. Each plan should show only the relevant partition being scanned, proving that the planner prunes the others.

```
[paste real output here]
```

## Cloud design highlights

See `cloud_design.md` for the full design. The key decisions:

1. **Synchronous replication for the ledger.** The primary and one standby are in two Availability Zones within the same region, with `synchronous_commit = on` and `synchronous_standby_names` set to require the standby's ACK before commit. A bank cannot lose a committed transaction.
2. **Asynchronous read replica for reporting.** A third instance, in a third AZ, receives the data via logical replication with `synchronous_commit = off`. Portfolio 2 aggregate queries run here so they never block writes.
3. **MongoDB replica set** for `transaction_events` and `fraud_alerts`, with `w: "majority"` write concern.
4. **Backups:** continuous WAL archiving, daily snapshots, monthly restore drills. RTO 1 hour, RPO 10 minutes.
5. **Data residency:** the primary and standby are hosted in Nigeria. No cross-border transfer of personal data occurs. The residency analysis references NDPA 2023 and CBN supervisory expectations, with an explicit note that the production deployment must be reviewed by LMB's legal and compliance team.

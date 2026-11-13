# Cloud Database Design - Lagos Meridian Bank

**Student:** Johnson Kazeem | **Matric:** 2026/A/MIT/0691

## 1. Objective

Design a managed-database deployment for Lagos Meridian Bank (LMB) that meets the operational needs of a Nigerian deposit money bank and complies with Nigerian data-protection and CBN supervisory expectations. The ledger is the most safety-critical dataset: it is the system of record for every customer balance and must not lose a single committed transaction.

## 2. Workload summary

| Workload | Pattern | Tolerance for data loss | Replication mode |
| --- | --- | --- | --- |
| Core ledger (`transfer`, `ledger_entry`, `account`) | OLTP, high write rate, low latency | Zero | Synchronous (multi-AZ) |
| Standing orders and settlement queue | OLTP, bursty | Zero | Synchronous (multi-AZ) |
| Reporting and BI copies | Read-heavy aggregates | Minutes (re-derivable) | Asynchronous (read replica) |
| MongoDB audit and fraud events | Append-heavy event log | Seconds | Asynchronous replica acceptable for analytics |

## 3. Managed-database architecture

```
                       +-----------------------------+
                       |  Application tier (Lagos)   |
                       |  Internet banking + USSD    |
                       +--------------+--------------+
                                      |
                          (primary write path)
                                      v
       +----------------------------+---------------------------+
       |  Primary (read-write)  AZ-a  <-- synchronous stream -->  |  Sync replica AZ-b
       |  PostgreSQL 16 managed   |                              |  PostgreSQL 16 managed
       |  ledger + accounts       |                              |  (hot standby, automatic failover)
       +------------+--------------+---------------------------+--+--------------+
                    |                                          |
                    | logical replication (async)              | logical replication (async)
                    v                                          v
       +------------+--------------+              +------------+--------------+
       |  Read replica (BI/ETL)   |              |  MongoDB replica set      |
       |  PostgreSQL 16            |              |  transaction_events,      |
       +---------------------------+              |  fraud_alerts              |
                                                  +---------------------------+
```

### 3.1 Multi-AZ synchronous primary

- The primary and one synchronous standby are placed in **two separate Availability Zones** within the same region.
- `synchronous_commit = on` and `synchronous_standby_names = FIRST 1 (lmb_sync)` - the primary waits for the standby to flush the WAL record before reporting commit to the application.
- Automatic failover is handled by the managed service's cluster manager (Patroni or cloud-native equivalent). The failover target is always the synchronous standby, so no committed transaction is lost.

### 3.2 Asynchronous read replica for reporting

- A third PostgreSQL instance, in a third AZ, is a logical replication subscriber.
- `synchronous_commit = off` on the subscriber - reports can lag by seconds; they never block writes on the primary.
- All Portfolio 2 aggregate queries (daily value per branch, failed-transfer rate, top customers by volume) run against this replica so they cannot starve the write path.

### 3.3 MongoDB replica set

- `transaction_events` and `fraud_alerts` run on a 3-node replica set: one primary, two secondaries.
- Writes are acknowledged when a majority of nodes have replicated (`w: "majority"`), which protects against rollback of fraud alerts.
- A hidden secondary is used for analytics and the bulk-index demo from Portfolio 4.

### 3.4 Backups

- **Continuous WAL archiving** to object storage every 5-10 minutes - supports point-in-time recovery to the last archived WAL segment.
- **Daily snapshot** of the cluster volume - retained 30 days, encrypted at rest with a customer-managed key.
- **Cross-region snapshot copy** to a secondary region (see section 5 on residency) - weekly, retained 90 days for disaster recovery.
- Restore drills are scheduled monthly and timed; the recovery time objective (RTO) is 1 hour and the recovery point objective (RPO) is 10 minutes.

## 4. Synchronous vs asynchronous replication - why the ledger must be synchronous

A bank's ledger is the legal record of who owns what. Two properties are non-negotiable:

1. **Durability of commit.** When the teller's screen says "transfer settled", the debit and credit ledger entries are persisted on at least two independent failure domains. If the primary is lost immediately after commit, the standby must have the transaction - otherwise the customer's balance is wrong and the bank's books do not reconcile.
2. **No split-brain on failover.** With synchronous replication and a quorum-based cluster manager, only one node can accept writes at a time. An asynchronous design can lose the last few transactions on failover; for a payments system this can mean a customer pays for a service that the bank has no record of, or the bank debits an account twice.

The cost of synchronous replication is latency: each commit waits for a round trip to the standby. For a Lagos-primary, Lagos-standby deployment the round-trip latency is sub-millisecond and the cost is acceptable. For cross-region replication (outside Nigeria), the latency would be unacceptable for the write path - see section 6.

Reporting, analytics and audit logs (MongoDB) can tolerate seconds of lag, so they use asynchronous replication. This keeps write latency on the primary low even when the reporting workload spikes.

## 5. Cloud regions and the Nigerian data-residency question

### 5.1 Hyperscaler regions in Africa

| Provider | Region name | Location |
| --- | --- | --- |
| AWS | `af-south-1` | Cape Town, South Africa |
| Microsoft Azure | `South Africa North` | Johannesburg, South Africa |
| Microsoft Azure | `South Africa West` | Cape Town, South Africa |
| Google Cloud | `africa-south1` | Johannesburg, South Africa |

None of the three hyperscalers operate a region inside Nigeria as at the time of writing. The closest available regions are in South Africa, ~5,000 km from Lagos, with round-trip latencies of 30-50 ms.

### 5.2 Nigerian data-protection and CBN supervisory context

- **Nigeria Data Protection Act 2023 (NDPA 2023)** establishes the Nigeria Data Protection Commission and requires data controllers to lawfully process personal data, to obtain consent where required, to notify the Commission of data breaches, and to impose equivalent protection on any cross-border transfer. Personal data may only be transferred to a foreign country whose data-protection regime is deemed adequate by the Commission, or under approved safeguards (for example, standard contractual clauses). NDPA 2023 does not by itself mandate that the data physically reside in Nigeria, but it does require that any transfer outside Nigeria meet its adequacy or safeguards test.
- **Central Bank of Nigeria supervisory expectations.** CBN's risk-based supervision framework and its ICT risk-management and outsourcing guidance expect deposit money banks to maintain effective control over customer data, to obtain CBN's no-objection before outsourcing material functions, and to ensure that supervisory access to data is preserved regardless of where the data is processed. The CBN has, in practice, questioned arrangements that place customer data outside Nigeria without a clear legal basis.

### 5.3 The residency question for LMB

For Lagos Meridian Bank, customer account data, BVN, balances, and the transfer ledger are personal and financial data. Two options are open:

1. **Nigeria-hosted primary.** Run the PostgreSQL primary and synchronous standby on a Nigerian provider (Galaxy Backbone, MTN Nigeria Cloud, MainOne / Equinix Lagos) or on private colocation in Lagos. This keeps the data physically in Nigeria, satisfies the supervisory-access expectation, and avoids any cross-border transfer analysis under NDPA 2023.
2. **Hyperscaler with documented cross-border transfer.** Use `af-south-1` (AWS) or `South Africa North` (Azure) for the primary, with a documented NDPA 2023 transfer impact assessment, standard contractual clauses with the hyperscaler, and a no-objection from the CBN. This option adds 30-50 ms of replication latency to the synchronous standby and must be revisited any time CBN updates its guidance.

The design in this document assumes option 1 (Nigeria-hosted primary) because it is the most defensible position under the NDPA 2023 cross-border transfer rules and CBN supervisory access expectations. The cross-region async replica in section 3.4 is itself hosted in a second Nigerian site, not outside Nigeria, so no cross-border transfer of personal data occurs.

**Important caveat:** the residency analysis above is a portfolio-level design exercise. A production deployment must be reviewed by LMB's legal and compliance team against the current text of NDPA 2023, the NDPC's regulations and guidance, and the CBN's prevailing outsourcing and data-governance circulars, all of which may change.

## 6. Partitioning and scaling strategy

- The `ledger_entry` table is partitioned by month on `created_at` (see `01_partitioning.sql`). Monthly partitions keep each index B-tree small and let the planner prune partitions for date-bounded queries.
- The primary key on the partitioned parent is `(ledger_id, created_at)` - PG16 requires every unique key on a partitioned table to include the partition key.
- PG16 does not allow exclusion constraints on a partitioned parent, so no `EXCLUDE USING` constraint is declared on `ledger_entry_part`.
- Old partitions (older than the retention period, e.g. 7 years per CBN record-keeping expectations) can be detached and archived to cold storage.

## 7. Operational runbook (summary)

| Activity | Frequency | Tool |
| --- | --- | --- |
| WAL archive check | Every 5 min | Managed service health metric |
| Daily snapshot | Daily | Managed service |
| Restore drill | Monthly | Documented runbook with timed RTO |
| Replica lag alert | Continuous | Alert if sync replica lag > 1 s or async replica lag > 60 s |
| Encryption key rotation | Annually | Cloud KMS |
| Patching (minor version) | Monthly | Managed service maintenance window |

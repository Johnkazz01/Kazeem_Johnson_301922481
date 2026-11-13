# Portfolio 3 - Transactions and Concurrency

**Student:** Johnson Kazeem | **Matric:** 2026/A/MIT/0691 | **Database:** `txnbank`

## Overview

This portfolio demonstrates ACID transactions and concurrency control on the Lagos Meridian Bank schema. It has two parts: a SQL script with three transaction demos (commit, rollback, SAVEPOINT recovery), and a Python script with six labelled concurrency demonstrations.

## Files

| File | Purpose |
| --- | --- |
| `01_transactions.sql` | Demo 1 - a committed funds transfer (debit + credit in one transaction). Demo 2 - a rolled-back transfer (nothing persists). Demo 3 - a SAVEPOINT recovery inside a bulk salary payment where one bad row is skipped and the rest of the batch still commits. |
| `race_demos.py` | Six concurrency scenarios run with two real psycopg2 sessions on separate threads. |

## Running

```bash
psql -d txnbank -v ON_ERROR_STOP=1 -f 01_transactions.sql
python3 race_demos.py
```

`race_demos.py` connects over the Unix socket with `psycopg2.connect(dbname="txnbank")` - no user, no password.

## Transaction demos (01_transactions.sql)

1. **Committed transfer.** Account 2 debits 5,000 NGN, account 3 credits 5,000 NGN, all inside one `BEGIN ... COMMIT`. The BEFORE and AFTER balance snapshots show the change. The script cleans up the demo transfer afterwards and recomputes balances so the database is left as it started.

2. **Rolled-back transfer.** Same shape as demo 1, but ends with `ROLLBACK`. The AFTER snapshot shows balances unchanged and the transfer row is absent. This is the proof that a rolled-back transaction does not affect committed state.

3. **SAVEPOINT recovery in bulk salary.** A corporate payroll account (11) pays 9 beneficiaries. Before the loop, the first item's amount is sabotaged to 100,000,000 NGN which exceeds the corporate overdraft limit (5,000,000 NGN). The loop processes each item inside a `BEGIN ... EXCEPTION` block - the PL/pgSQL equivalent of a SAVEPOINT. When the bad item's debit fails, only that item's changes are rolled back, the item is marked FAILED, and the loop continues. The other 8 items are marked PAID. The script cleans up after itself.

## Race demos (race_demos.py)

| Part | Scenario | Expected outcome |
| --- | --- | --- |
| 1 | The bug | Two workers both `SELECT ... WHERE status='PENDING'` without a lock and target the same transfer. One worker either duplicates the settlement or fails with a `check_violation` from the balanced-ledger trigger. |
| 2 | UNIQUE constraint fix | A `settlement_claim(transfer_id UNIQUE)` table rejects the second worker's `INSERT` with a clean `unique_violation` instead of an obscure ledger error. |
| 3 | FOR UPDATE SKIP LOCKED | Each worker's `SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1` skips rows already locked by the other worker, so each settles a different transfer. |
| 4 | SERIALIZABLE | Both workers run at `ISOLATION_LEVEL_SERIALIZABLE`. One commits and the other is aborted with SQLSTATE `40001` (`serialization_failure`). |
| 5 | READ COMMITTED vs REPEATABLE READ | A reader and a writer run concurrently. The READ COMMITTED reader sees the writer's committed update; the REPEATABLE READ reader sees the original snapshot. |
| 6 | Deadlock (40P01) and fix | 6a: two workers lock accounts in opposite orders and one is aborted with SQLSTATE `40P01`. 6b: both workers lock accounts in `id` order and both commit. |

## The race-condition fix required by the brief

The brief mandates `SELECT ... FOR UPDATE SKIP LOCKED` on the settlement queue. Part 3 is that fix: a worker reads the next `PENDING` transfer with `FOR UPDATE SKIP LOCKED`, which atomically locks the row and skips any row already locked by another worker. The two workers therefore never settle the same transfer.

Parts 2 and 4 are alternative fixes shown for comparison:
- Part 2 uses a UNIQUE constraint on a claim table - a defensive second line of defence.
- Part 4 uses SERIALIZABLE isolation - correct but at the cost of retry-on-40001 overhead.

Part 1 (the bug) and Part 6 (deadlock) show what goes wrong without the fix.

## Output

The script prints labelled sections. Paste the real output below after running:

```
[paste real output here]
```

## Notes

- The demos create their own rows (reference prefixes `RACE-BUG-%`, `RACE-UNIQ-%`, `RACE-SKIP-%`, `RACE-SER-%`, `RACE-ISO-%`, `RACE-DEAD-%`) and delete them at the end so the database is left clean.
- `race_demos.py` does not use `pg_sleep` tricks that need hand-pasting. Each demo synchronises workers with a `threading.Barrier(2)` so both reach the critical `SELECT` at the same time.
- The deadlock demo uses a short `time.sleep(0.3)` between locking the first and second account, which is enough to provoke the deadlock reliably on a single host; this is not a `pg_sleep` inside SQL.

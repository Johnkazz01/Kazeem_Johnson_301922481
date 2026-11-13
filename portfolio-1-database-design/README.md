# Portfolio 1 - Database Design

**Student:** Johnson Kazeem | **Matric:** 2026/A/MIT/0691 | **Database:** `txnbank`

## Overview

This portfolio implements the relational schema for Lagos Meridian Bank's transaction banking system in PostgreSQL 16. The schema has 10 tables in third normal form, with primary keys, foreign keys, UNIQUE constraints, CHECK constraints, one partial UNIQUE index, and three business-rule triggers.

## Files

| File | Purpose |
| --- | --- |
| `01_schema.sql` | Creates the 10 tables, the partial UNIQUE index, and the 3 trigger functions + triggers. Sets the database time zone to `Africa/Lagos`. |
| `02_indexes.sql` | B-tree indexes on every FK column that triggers or reports use, plus composite indexes for the account statement and branch daily aggregate reports. |
| `03_seed_data.sql` | Seeds 6 branches, 4 account types, 16 customers (1 capital holder, 9 individuals with gender-matched Nigerian names, 6 corporates), 17 accounts, 6 fee schedule rows, 3 settlement batches, opening-balance transfers for every account, 6 standing orders (with future-dated runs), and a 9-item corporate salary bulk payment batch. |
| `04_bulk_data.sql` | Generates 50,000 transfers and 88,000 ledger entries with `generate_series` (no Python loops). Dates are relative to today with a 14-day forward window. Triggers are temporarily disabled and balances are recomputed from the ledger so the load completes under 30 seconds. |
| `05_constraint_tests.sql` | 10 tests that must fail on the intended constraint (CHECK, UNIQUE, FK, trigger, partial UNIQUE index) plus 1 control test that must succeed. Each test is wrapped in `BEGIN ... ROLLBACK` and prints PASS or FAIL. |

## Running

```bash
psql -d txnbank -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -d txnbank -v ON_ERROR_STOP=1 -f 02_indexes.sql
psql -d txnbank -v ON_ERROR_STOP=1 -f 03_seed_data.sql
psql -d txnbank -v ON_ERROR_STOP=1 -f 04_bulk_data.sql
psql -d txnbank -v ON_ERROR_STOP=1 -f 05_constraint_tests.sql
```

All five files run top to bottom with `ON_ERROR_STOP=1` and need no manual edits.

## Schema summary

- `branch` - physical bank locations keyed by a short code.
- `customer` - individuals and corporates; BVN is UNIQUE.
- `account_type` - product definitions with overdraft flag and limit.
- `account` - customer account instances with NUBAN-style number and status.
- `transfer` - the movement of funds; status `PENDING`/`SETTLED`/`FAILED`/`REVERSED`.
- `ledger_entry` - double-entry debit/credit lines.
- `standing_order` - recurring transfer instructions.
- `settlement_batch` - groups of transfers settled together.
- `fee_schedule` - tariff definitions (flat or percent).
- `bulk_payment_item` - per-beneficiary line items in a corporate salary batch.

## Triggers

1. **`trg_check_account_status`** (BEFORE INSERT/UPDATE on `ledger_entry`) - rejects debits or credits on `CLOSED` or `FROZEN` accounts.
2. **`trg_check_debit_balance`** (BEFORE INSERT/UPDATE on `ledger_entry`) - rejects debits that would take a non-overdraft account below zero, or push an overdraft account past its limit. Also maintains the cached `account.balance` so that it always equals `SUM(credits) - SUM(debits)` for that account.
3. **`trg_transfer_balanced`** (AFTER INSERT/UPDATE on `ledger_entry`) - enforces that every transfer with at least two ledger entries has equal total debits and credits.
4. **`trg_standing_order_dates`** (BEFORE INSERT/UPDATE on `standing_order`) - rejects an `ACTIVE` standing order whose `end_date` is in the past. This replaces a `CHECK ... CURRENT_DATE` constraint, which is disallowed by the portfolio rules.

## Partial UNIQUE index

```sql
CREATE UNIQUE INDEX uq_active_standing_order
    ON standing_order (debit_account_id, credit_account_id, purpose)
    WHERE status = 'ACTIVE';
```

This enforces "one ACTIVE standing order per debit account per beneficiary per purpose". PAUSED or CANCELLED orders do not occupy the slot, so a cancelled order can be replaced by a new ACTIVE one.

## Balance integrity

The `account.balance` column is a cached value maintained by the `trg_check_debit_balance` trigger. It is never set by application `INSERT` or `UPDATE` statements. The `04_bulk_data.sql` script disables user triggers during the bulk load and then recomputes `account.balance` directly from the ledger with a single `UPDATE ... FROM (SELECT ... SUM ... GROUP BY)` statement; a verification query at the end of the script asserts that every cached balance matches the ledger sum. The output of that verification is:

```
[paste real output here]
```

## Bulk data approach

The bulk data is generated with `generate_series(1, 50000)` inside SQL - no Python loops. 88% of transfers are `SETTLED` (and therefore have 2 ledger entries each), 8% are `FAILED`, and 4% are `PENDING` with `created_at` up to 14 days in the future. Amounts are deterministic from the generate_series index so the data is reproducible. The bulk load on the sandbox hardware took:

```
[paste real output here]
```

## Constraint tests

The 10 failing tests and 1 control test in `05_constraint_tests.sql` produce output like:

```
[paste real output here]
```

Every failing test should print `PASS: <name> - <error message>` and the control test should print `PASS: control_valid_transfer - balanced 1000 NGN transfer posted successfully`.

# CHANGES - Johnson Kazeem (2026/A/MIT/0691), Transaction Banking System (txnbank)

Tested as a non-root user over the Unix socket (no TCP, no passwords) on PostgreSQL 16 and MongoDB 8. Full clean run of runall.sh: P1 to P5 all complete (about 20 s).

| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | P1 04_bulk_data.sql | `make_interval(minutes => 5)` does not exist, bulk load stopped | replaced with `interval '5 minutes'` | 50,000 transfers, 92,000 ledger entries; balance check PASS |
| 2 | P1 05_constraint_tests.sql | test account numbers (`TEST-CLOSED-01` etc.) longer than VARCHAR(12) | replaced with 10-digit numbers | closed, frozen, overdraft and control tests all PASS |
| 3 | P1 05_constraint_tests.sql | PL/pgSQL variable `transfer_id` clashed with the column name (ambiguous) | renamed variable to `v_tid` | 11 of 11 tests PASS |
| 4 | P3 race_demos.py | `cleanup_demo` deleted from `settlement_claim` before the table existed | removed that line; delete claims only if the table exists, before deleting transfers (FK) | script runs end to end |
| 5 | P3 race_demos.py | `exec_one` returned before `commit()`, so seeded rows were never saved ("no transfer found"); empty params made psycopg2 read `%` in `LIKE` as a format code | commit before return; pass params as given | Parts 1 to 6 all run |
| 6 | P3 race_demos.py | `%d` inside SQL text (Parts 1 and 3) raised "unsupported format character" | pass the worker number as a `%s` parameter | Part 1 shows the race (one worker fails with unbalanced ledger), Part 3 SKIP LOCKED settles two different transfers, Part 4 gives 40001, Part 6 gives 40P01 then the ordered version commits |
| 7 | P4 01_setup.js | `getInfo()` is not a function | use `db.getCollectionInfos({name: ...})` | validators print |
| 8 | P4 03_bulk_and_index_demo.js | message counted the wrong field (printed "Inserted 0"); query returned 20% of the collection, so the index showed no gain | count on `event_id`; query made selective (`amount >= 5800`) | 40,000 docs; COLLSCAN 40,012 examined 16 ms to IXSCAN 538 examined 3 ms |
| 9 | setup.sh (added) | missing | written: `runuser -u postgres`, role and db `txnbank`, Lagos time zone, mongod, psycopg2 fallback chain with verify | runs clean as non-root |
| 10 | run_p1 to run_p5.sh, runall.sh, collect_results.sh (added) | missing | `set -euo pipefail`, one log per portfolio, commit and push after each, stops with a clear message on failure, ends with my_results.txt | P1 to P5 COMPLETE |
| 11 | P5 02_replica_setup.sh, 03_replica_tests.sql (added) | missing | streaming replica on port 55432 over the socket (hba line at the top, minimal conf, chmod 700); one test script switches servers | replica in_recovery = t; write on replica rejected; row inserted on primary appears on replica |

## Checks that already passed (no change needed)
- Balances come from the ledger: cached balances match SUM of ledger entries.
- Debits equal credits: 0 unbalanced transfers.
- FAILED transfers carry no ledger entries, so reversing one creates no money: 0 ledger rows for the 2,000 FAILED transfers.
- No card number, CVV or PIN columns anywhere.
- No names, matric numbers or DB names from other students (checked with grep).

## Cut / simplified
- No separate reference zip was attached, so the runner, setup and replica scripts were written fresh for this project rather than copied.
- Not re-tested: psycopg2 uninstalled, or the kit folder missing (runall.sh re-unzips the zip and re-runs setup in those cases).
- P5 replica is a local streaming replica only (no backup or promotion steps).

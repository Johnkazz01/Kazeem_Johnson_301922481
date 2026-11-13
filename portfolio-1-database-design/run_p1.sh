#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
psql -d txnbank -c "ALTER DATABASE txnbank SET timezone TO 'Africa/Lagos'"
for f in 01_schema 02_indexes 03_seed_data 04_bulk_data 05_constraint_tests; do echo "=== P1 $f"; psql -d txnbank -v ON_ERROR_STOP=1 -f $f.sql; done
echo "=== P1 ledger checks"
psql -d txnbank -c "SELECT count(*) AS unbalanced_transfers FROM (SELECT transfer_id FROM ledger_entry GROUP BY 1 HAVING sum(CASE direction WHEN 'DEBIT' THEN amount ELSE -amount END)<>0) x"
psql -d txnbank -c "SELECT count(*) AS failed_transfers_with_ledger_entries FROM ledger_entry l JOIN transfer t USING(transfer_id) WHERE t.status='FAILED'"
echo "P1 COMPLETE"

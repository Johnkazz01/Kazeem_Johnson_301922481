#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== P3 transactions"; psql -d txnbank -v ON_ERROR_STOP=1 -f 01_transactions.sql
echo "=== P3 race demos"; python3 race_demos.py 2>&1 | tee race_demos_output.log
echo "P3 COMPLETE"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== P2 queries"; psql -d txnbank -v ON_ERROR_STOP=1 -f 01_queries.sql > queries_output.txt
echo "=== P2 explain analyze (before/after)"; psql -d txnbank -v ON_ERROR_STOP=1 -f 02_explain_analyze.sql | tee explain_output.txt
echo "P2 COMPLETE"

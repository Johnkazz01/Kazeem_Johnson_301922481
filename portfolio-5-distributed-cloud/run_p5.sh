#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== P5 partitioning"; psql -d txnbank -v ON_ERROR_STOP=1 -f 01_partitioning.sql
echo "=== P5 replica setup"; bash 02_replica_setup.sh 2>&1 | tee replication_output.log
echo "=== P5 replica tests"; psql -d txnbank -f 03_replica_tests.sql 2>&1 | tee -a replication_output.log
echo "P5 COMPLETE"

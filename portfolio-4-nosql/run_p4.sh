#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
pgrep -x mongod >/dev/null || sudo runuser -u mongodb -- mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1 && break; sleep 1; done
for f in 01_setup 02_data_and_queries 03_bulk_and_index_demo; do echo "=== P4 $f"; mongosh --quiet --file $f.js; done
echo "P4 COMPLETE"

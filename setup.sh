#!/usr/bin/env bash
# setup.sh - Johnson Kazeem, 2026/A/MIT/0691 - prepares PostgreSQL (txnbank), MongoDB and Python packages.
set -euo pipefail
sudo rm -f /etc/apt/sources.list.d/yarn.list || true
sudo apt-get update -y >/dev/null 2>&1 || true
sudo apt-get install -y postgresql postgresql-contrib python3-psycopg2 python3-pymongo >/dev/null 2>&1 || true
sudo pg_ctlcluster 16 main start 2>/dev/null || sudo service postgresql start || true
for i in 1 2 3 4 5 6 7 8 9 10; do sudo runuser -u postgres -- psql -c 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done
ME="$(whoami)"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$ME') THEN CREATE ROLE \"$ME\" SUPERUSER LOGIN; END IF; END \$\$;"
sudo runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='txnbank'" | grep -q 1 || sudo runuser -u postgres -- createdb -O "$ME" txnbank
psql -d txnbank -c "ALTER DATABASE txnbank SET timezone TO 'Africa/Lagos'"
# MongoDB (skipped quietly if already installed)
if ! command -v mongod >/dev/null 2>&1; then
  sudo apt-get install -y mongodb-org >/dev/null 2>&1 || sudo apt-get install -y mongodb >/dev/null 2>&1 || echo "NOTE: install mongod manually if P4 fails"
fi
command -v mongosh >/dev/null 2>&1 || npm i -g mongosh >/dev/null 2>&1 || sudo npm i -g mongosh >/dev/null 2>&1 || true
sudo mkdir -p /data/db /var/log/mongodb; sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || sudo chmod -R 777 /data/db /var/log/mongodb
pgrep -x mongod >/dev/null || sudo runuser -u mongodb -- mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null 2>&1 || true
# Python packages: fallback chain, then verify
python3 -c 'import psycopg2, pymongo' 2>/dev/null || pip install psycopg2-binary pymongo 2>/dev/null || pip install --user psycopg2-binary pymongo 2>/dev/null || pip install --break-system-packages psycopg2-binary pymongo 2>/dev/null || pip install --user --break-system-packages psycopg2-binary pymongo 2>/dev/null || sudo apt-get install -y python3-psycopg2 python3-pymongo
python3 -c 'import psycopg2, pymongo; print("python packages OK")'
echo "setup complete"

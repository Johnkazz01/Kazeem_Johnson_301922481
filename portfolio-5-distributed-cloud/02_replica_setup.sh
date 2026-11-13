#!/usr/bin/env bash
# 02_replica_setup.sh - Johnson Kazeem, 2026/A/MIT/0691
# Builds a streaming read-only replica of txnbank on port 55432 using Unix sockets (no TCP, no passwords).
set -euo pipefail
PGBIN=/usr/lib/postgresql/16/bin
CONF=/etc/postgresql/16/main
REPL=/var/lib/postgresql/replica16
PG="sudo runuser -u postgres --"
# 1. replication line at the TOP of pg_hba.conf (Ubuntu's later rules would otherwise win)
if ! sudo grep -q "txnbank-replica" $CONF/pg_hba.conf; then
  sudo cp $CONF/pg_hba.conf $CONF/pg_hba.conf.bak_txnbank
  { echo "local replication all trust # txnbank-replica"; sudo cat $CONF/pg_hba.conf; } | sudo tee $CONF/pg_hba.conf.new >/dev/null
  sudo mv $CONF/pg_hba.conf.new $CONF/pg_hba.conf
  sudo chown postgres:postgres $CONF/pg_hba.conf
fi
$PG psql -qc "ALTER SYSTEM SET wal_level='replica'" -c "ALTER SYSTEM SET max_wal_senders=5" >/dev/null
sudo pg_ctlcluster 16 main restart
sleep 2
# 2. stop and remove any old replica
$PG $PGBIN/pg_ctl -D $REPL stop -m fast >/dev/null 2>&1 || true
sudo rm -rf $REPL
# 3. base backup over the Unix socket
$PG $PGBIN/pg_basebackup -h /var/run/postgresql -p 5432 -D $REPL -R -X stream
# 4. Ubuntu keeps config in /etc, so write a minimal config for the replica
sudo cp $CONF/pg_hba.conf $REPL/pg_hba.conf
sudo cp $CONF/pg_ident.conf $REPL/pg_ident.conf
sudo chown postgres:postgres $REPL/pg_hba.conf $REPL/pg_ident.conf
printf "port = 55432\nunix_socket_directories = '/var/run/postgresql'\nlisten_addresses = ''\nhot_standby = on\nhba_file = '$REPL/pg_hba.conf'\nident_file = '$REPL/pg_ident.conf'\nmax_wal_senders = 5\nwal_level = replica\n" | sudo tee $REPL/postgresql.conf >/dev/null
sudo chown postgres:postgres $REPL/postgresql.conf
sudo chmod 700 $REPL
$PG $PGBIN/pg_ctl -D $REPL -l /tmp/replica16.log -o "-c config_file=$REPL/postgresql.conf" -w start
echo "replica started on port 55432"

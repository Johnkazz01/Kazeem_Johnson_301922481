-- 03_replica_tests.sql - Johnson Kazeem, 2026/A/MIT/0691
-- Run with: psql -d txnbank -f 03_replica_tests.sql  (switches between primary 5432 and replica 55432 over the socket)
\set ON_ERROR_STOP off
\echo === 1. Who is who ===
\connect -reuse-previous=off txnbank - /var/run/postgresql 5432
SELECT 'primary' AS expected, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\connect -reuse-previous=off txnbank - /var/run/postgresql 55432
SELECT 'replica' AS expected, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\echo === 2. Write on the replica must be rejected ===
INSERT INTO branch (code, name, address, lga, state, opened_on) VALUES ('RPL-TEST01','Replica test','1 Test Street','Eti-Osa','Lagos',CURRENT_DATE);
\echo === 3. Insert on the primary, then read it on the replica ===
\connect -reuse-previous=off txnbank - /var/run/postgresql 5432
DELETE FROM branch WHERE code = 'RPL-TEST01';
INSERT INTO branch (code, name, address, lga, state, opened_on) VALUES ('RPL-TEST01','Replica test','1 Test Street','Eti-Osa','Lagos',CURRENT_DATE);
SELECT pg_sleep(1);
SELECT client_addr IS NULL AS via_socket, state, sync_state FROM pg_stat_replication;
\connect -reuse-previous=off txnbank - /var/run/postgresql 55432
SELECT code, name FROM branch WHERE code = 'RPL-TEST01';
SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag, pg_last_wal_replay_lsn() AS replica_lsn;
\connect -reuse-previous=off txnbank - /var/run/postgresql 5432
DELETE FROM branch WHERE code = 'RPL-TEST01';
\echo === replica tests done ===

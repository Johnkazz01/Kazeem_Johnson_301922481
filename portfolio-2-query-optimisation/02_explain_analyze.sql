-- 02_explain_analyze.sql
-- EXPLAIN (ANALYZE, BUFFERS) for the 4 selective queries from 01_queries.sql,
-- run twice: once with the P2 supporting indexes dropped, and once with them
-- recreated. The supporting indexes are the composite ones added in
-- portfolio-1/02_indexes.sql specifically for the account statement and the
-- last-30-days reports. The FK indexes on transfer(debit_account_id) etc. are
-- kept because they back the foreign keys themselves and cannot be dropped
-- without dropping the constraint.
--
-- HONESTY NOTE: the aggregate queries (Q5-Q8) intentionally keep a Seq Scan even
-- after the supporting indexes are recreated, because they scan most of the
-- transfer table and an index would not help. See README.md for the explanation.

SET timezone TO 'Africa/Lagos';

\echo '======================================================================'
\echo 'PHASE 1: EXPLAIN ANALYZE with supporting P2 indexes DROPPED'
\echo '======================================================================'

DROP INDEX IF EXISTS idx_ledger_account_date;
DROP INDEX IF EXISTS idx_transfer_created_debit;
DROP INDEX IF EXISTS idx_transfer_created_at;

\echo '--- Q1 (account statement) BEFORE index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT le.ledger_id, le.created_at, le.direction, le.amount, le.narration, t.reference, t.status
FROM ledger_entry le
JOIN transfer t ON t.transfer_id = le.transfer_id
WHERE le.account_id = 2
  AND le.created_at >= now() - make_interval(days => 60)
ORDER BY le.created_at DESC
LIMIT 50;

\echo '--- Q2 (branch report) BEFORE index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.reference, t.amount, t.status, t.channel, t.created_at,
       da.account_number, ca.account_number
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN account ca ON ca.account_id = t.credit_account_id
WHERE da.branch_id = 1
  AND t.created_at >= now() - make_interval(days => 30)
ORDER BY t.created_at DESC
LIMIT 50;

\echo '--- Q3 (customer report) BEFORE index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.reference, t.amount, t.status, t.channel, t.created_at,
       CASE WHEN dc.customer_id = 2 THEN 'DEBIT' ELSE 'CREDIT' END AS role
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN customer dc ON dc.customer_id = da.customer_id
JOIN account ca ON ca.account_id = t.credit_account_id
JOIN customer cc ON cc.customer_id = ca.customer_id
WHERE 2 IN (dc.customer_id, cc.customer_id)
ORDER BY t.created_at DESC
LIMIT 50;

\echo '--- Q4 (last 30 days) BEFORE index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.reference, t.amount, t.status, t.channel, t.created_at,
       da.account_number, ca.account_number
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN account ca ON ca.account_id = t.credit_account_id
WHERE t.created_at >= now() - make_interval(days => 30)
ORDER BY t.created_at DESC
LIMIT 100;

\echo '======================================================================'
\echo 'PHASE 2: recreate the supporting P2 indexes'
\echo '======================================================================'

CREATE INDEX IF NOT EXISTS idx_ledger_account_date   ON ledger_entry(account_id, created_at);
CREATE INDEX IF NOT EXISTS idx_transfer_created_debit ON transfer(created_at, debit_account_id);
CREATE INDEX IF NOT EXISTS idx_transfer_created_at    ON transfer(created_at);

ANALYZE ledger_entry;
ANALYZE transfer;

\echo '======================================================================'
\echo 'PHASE 3: EXPLAIN ANALYZE with supporting P2 indexes RECREATED'
\echo '======================================================================'

\echo '--- Q1 (account statement) AFTER index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT le.ledger_id, le.created_at, le.direction, le.amount, le.narration, t.reference, t.status
FROM ledger_entry le
JOIN transfer t ON t.transfer_id = le.transfer_id
WHERE le.account_id = 2
  AND le.created_at >= now() - make_interval(days => 60)
ORDER BY le.created_at DESC
LIMIT 50;

\echo '--- Q2 (branch report) AFTER index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.reference, t.amount, t.status, t.channel, t.created_at,
       da.account_number, ca.account_number
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN account ca ON ca.account_id = t.credit_account_id
WHERE da.branch_id = 1
  AND t.created_at >= now() - make_interval(days => 30)
ORDER BY t.created_at DESC
LIMIT 50;

\echo '--- Q3 (customer report) AFTER index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.reference, t.amount, t.status, t.channel, t.created_at,
       CASE WHEN dc.customer_id = 2 THEN 'DEBIT' ELSE 'CREDIT' END AS role
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN customer dc ON dc.customer_id = da.customer_id
JOIN account ca ON ca.account_id = t.credit_account_id
JOIN customer cc ON cc.customer_id = ca.customer_id
WHERE 2 IN (dc.customer_id, cc.customer_id)
ORDER BY t.created_at DESC
LIMIT 50;

\echo '--- Q4 (last 30 days) AFTER index ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.reference, t.amount, t.status, t.channel, t.created_at,
       da.account_number, ca.account_number
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN account ca ON ca.account_id = t.credit_account_id
WHERE t.created_at >= now() - make_interval(days => 30)
ORDER BY t.created_at DESC
LIMIT 100;

\echo '======================================================================'
\echo 'PHASE 4: aggregate query (Q5) - remains a Seq Scan by design'
\echo '======================================================================'

\echo '--- Q5 (daily transaction value per branch) AFTER index - still Seq Scan ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    b.code AS branch_code,
    DATE(t.created_at) AS txn_date,
    COUNT(*) AS txn_count,
    SUM(t.amount) AS total_value
FROM transfer t
JOIN account a ON a.account_id = t.debit_account_id
JOIN branch b ON b.branch_id = a.branch_id
WHERE t.status = 'SETTLED'
GROUP BY b.code, DATE(t.created_at)
ORDER BY txn_date DESC, total_value DESC
LIMIT 60;

\echo '=== Done. Paste the four BEFORE / AFTER pairs into README.md. ==='

-- 01_queries.sql
-- 8 reporting queries for Lagos Meridian Bank.
-- 4 selective (single account statement, single branch, single customer, last 30 days)
-- 4 full-table aggregates (daily transaction value per branch, top customers by volume,
-- failed-transfer rate, channel mix).
-- Each query is terminated with a semicolon and labelled with a \echo banner.

SET timezone TO 'Africa/Lagos';

\echo '=== Query 1: Account statement (selective) ==='
\echo 'All ledger entries for one account in the last 60 days, newest first.'
SELECT
    le.ledger_id,
    le.created_at,
    le.direction,
    le.amount,
    le.narration,
    t.reference,
    t.status AS transfer_status
FROM ledger_entry le
JOIN transfer t ON t.transfer_id = le.transfer_id
WHERE le.account_id = 2
  AND le.created_at >= now() - make_interval(days => 60)
ORDER BY le.created_at DESC
LIMIT 50;

\echo '=== Query 2: Branch report (selective) ==='
\echo 'All transfers where the debit account is held at a given branch, last 30 days.'
SELECT
    t.reference,
    t.amount,
    t.status,
    t.channel,
    t.created_at,
    da.account_number AS debit_account,
    ca.account_number AS credit_account
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN account ca ON ca.account_id = t.credit_account_id
WHERE da.branch_id = 1
  AND t.created_at >= now() - make_interval(days => 30)
ORDER BY t.created_at DESC
LIMIT 50;

\echo '=== Query 3: Customer report (selective) ==='
\echo 'All transfers where the customer is either the debit or credit account owner.'
SELECT
    t.reference,
    t.amount,
    t.status,
    t.channel,
    t.created_at,
    CASE WHEN dc.customer_id = 2 THEN 'DEBIT' ELSE 'CREDIT' END AS role
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN customer dc ON dc.customer_id = da.customer_id
JOIN account ca ON ca.account_id = t.credit_account_id
JOIN customer cc ON cc.customer_id = ca.customer_id
WHERE 2 IN (dc.customer_id, cc.customer_id)
ORDER BY t.created_at DESC
LIMIT 50;

\echo '=== Query 4: Last 30 days (selective) ==='
\echo 'Every transfer created in the last 30 days with both account numbers.'
SELECT
    t.reference,
    t.amount,
    t.status,
    t.channel,
    t.created_at,
    da.account_number AS debit_account,
    ca.account_number AS credit_account
FROM transfer t
JOIN account da ON da.account_id = t.debit_account_id
JOIN account ca ON ca.account_id = t.credit_account_id
WHERE t.created_at >= now() - make_interval(days => 30)
ORDER BY t.created_at DESC
LIMIT 100;

\echo '=== Query 5: Daily transaction value per branch (aggregate) ==='
SELECT
    b.code AS branch_code,
    b.name AS branch_name,
    DATE(t.created_at) AS txn_date,
    COUNT(*) AS txn_count,
    SUM(t.amount) AS total_value
FROM transfer t
JOIN account a ON a.account_id = t.debit_account_id
JOIN branch b ON b.branch_id = a.branch_id
WHERE t.status = 'SETTLED'
GROUP BY b.code, b.name, DATE(t.created_at)
ORDER BY txn_date DESC, total_value DESC
LIMIT 60;

\echo '=== Query 6: Top customers by transaction volume (aggregate) ==='
SELECT
    c.full_name,
    c.customer_type,
    COUNT(*) AS txn_count,
    SUM(t.amount) AS total_volume
FROM transfer t
JOIN account a ON a.account_id = t.debit_account_id
JOIN customer c ON c.customer_id = a.customer_id
WHERE t.status = 'SETTLED'
GROUP BY c.customer_id, c.full_name, c.customer_type
ORDER BY total_volume DESC
LIMIT 10;

\echo '=== Query 7: Failed-transfer rate (aggregate) ==='
SELECT
    DATE(t.created_at) AS txn_date,
    COUNT(*) FILTER (WHERE t.status = 'FAILED') AS failed_count,
    COUNT(*) AS total_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE t.status = 'FAILED') / NULLIF(COUNT(*), 0),
        2
    ) AS failed_rate_pct
FROM transfer t
GROUP BY DATE(t.created_at)
ORDER BY txn_date DESC
LIMIT 30;

\echo '=== Query 8: Channel mix (aggregate) ==='
SELECT
    t.channel,
    COUNT(*) AS txn_count,
    SUM(t.amount) AS total_value,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_txns
FROM transfer t
WHERE t.status = 'SETTLED'
GROUP BY t.channel
ORDER BY txn_count DESC;

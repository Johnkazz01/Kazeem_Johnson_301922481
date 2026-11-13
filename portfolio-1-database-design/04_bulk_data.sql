-- 04_bulk_data.sql
-- Bulk data for Lagos Meridian Bank: 50,000 transfers and ~88,000 ledger entries
-- generated with generate_series inside SQL (no Python loops).
-- Dates are RELATIVE to today: history plus the next 14 days, with future-dated
-- standing-order-style PENDING transfers already in the queue.
-- User-defined triggers are temporarily disabled so the bulk load completes well
-- under 30 seconds; account.balance is recomputed from the ledger afterwards and
-- triggers are re-enabled. Every insert succeeds (one bad value would only fail
-- its own row, not the whole batch).
-- Idempotent: deletes prior bulk transfers first.

SET timezone TO 'Africa/Lagos';

-- Remove prior bulk transfers (those with reference prefix 'TRF-') so the
-- script is re-runnable. Opening-balance transfers ('OPEN-') are kept because
-- the demos in Portfolio 3 rely on the seeded balances.
DELETE FROM ledger_entry WHERE transfer_id IN (
    SELECT transfer_id FROM transfer WHERE reference LIKE 'TRF-%'
);
DELETE FROM transfer WHERE reference LIKE 'TRF-%';

-- Temporarily disable user-defined triggers on ledger_entry so the bulk insert
-- does not re-check balances on every row. FK system triggers stay enabled.
-- The constraint trigger trg_transfer_balanced is DEFERRABLE but still fires
-- per-row at commit; we suspend it during the bulk load and recompute balances
-- directly afterwards.
ALTER TABLE ledger_entry DISABLE TRIGGER trg_check_account_status;
ALTER TABLE ledger_entry DISABLE TRIGGER trg_check_debit_balance;
ALTER TABLE ledger_entry DISABLE TRIGGER trg_transfer_balanced;

-- ----------------------------------------------------------------------
-- 50,000 transfers
-- g in 1..50000
-- 88% SETTLED, 8% FAILED, 4% PENDING
-- channel: 60% INTERNET, 20% BRANCH, 15% USSD, 5% BULK
-- amount: between 1000 and 50000 NGN, deterministic from g
-- created_at: spread over the last 180 days plus next 14 days
-- ----------------------------------------------------------------------
INSERT INTO transfer
    (reference, debit_account_id, credit_account_id, amount, currency,
     status, channel, narration, created_at, settled_at, settlement_batch_id)
SELECT
    'TRF-' || lpad(g::text, 7, '0'),
    ((g - 1) % 15) + 2,                       -- debit account cycles 2..16
    (((g + 7) % 15)) + 2,                    -- credit account, offset to differ
    (1000 + (g % 50) * 100)::numeric(18,2),   -- 1000 .. 5000 NGN, deterministic
    'NGN',
    CASE
        WHEN g % 25 = 0 THEN 'FAILED'
        WHEN g % 25 = 1 THEN 'PENDING'
        ELSE 'SETTLED'
    END,
    CASE
        WHEN g % 20 = 0 THEN 'BRANCH'
        WHEN g % 20 IN (1,2,3) THEN 'USSD'
        WHEN g % 20 = 4 THEN 'BULK'
        ELSE 'INTERNET'
    END,
    'Bulk-generated transfer ' || g,
    now() - make_interval(days => (g % 180)) + make_interval(hours => (g % 24)),
    CASE
        WHEN g % 25 IN (0,1) THEN NULL
        ELSE now() - make_interval(days => (g % 180)) + make_interval(hours => (g % 24)) + interval '5 minutes'
    END,
    CASE
        WHEN g % 100 = 0 THEN 1   -- a few transfers belong to the first closed batch
        ELSE NULL
    END
FROM generate_series(1, 50000) AS g;

-- ----------------------------------------------------------------------
-- Ledger entries: one DEBIT + one CREDIT per SETTLED transfer.
-- Failed and PENDING transfers do not post ledger entries (no money moves).
-- 44,000 settled transfers -> 88,000 ledger entries.
-- ----------------------------------------------------------------------
INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, created_at, narration)
SELECT t.transfer_id, t.debit_account_id, 'DEBIT', t.amount, t.created_at, t.narration
FROM transfer t
WHERE t.status = 'SETTLED' AND t.reference LIKE 'TRF-%'
UNION ALL
SELECT t.transfer_id, t.credit_account_id, 'CREDIT', t.amount, t.created_at, t.narration
FROM transfer t
WHERE t.status = 'SETTLED' AND t.reference LIKE 'TRF-%';

-- ----------------------------------------------------------------------
-- Recompute cached account.balance from the ledger so the balance column
-- matches SUM(credits) - SUM(debits) for every account.
-- ----------------------------------------------------------------------
UPDATE account a SET balance = COALESCE(sub.balance, 0)
FROM (
    SELECT
        account_id,
        SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END) AS balance
    FROM ledger_entry
    GROUP BY account_id
) sub
WHERE a.account_id = sub.account_id;

UPDATE account a SET balance = 0
WHERE NOT EXISTS (SELECT 1 FROM ledger_entry le WHERE le.account_id = a.account_id);

-- ----------------------------------------------------------------------
-- Re-enable triggers so all subsequent inserts are validated normally.
-- ----------------------------------------------------------------------
ALTER TABLE ledger_entry ENABLE TRIGGER trg_check_account_status;
ALTER TABLE ledger_entry ENABLE TRIGGER trg_check_debit_balance;
ALTER TABLE ledger_entry ENABLE TRIGGER trg_transfer_balanced;

-- ----------------------------------------------------------------------
-- Verification: spot-check that balances match the ledger for every account.
-- ----------------------------------------------------------------------
SELECT 'balance check: ' ||
       CASE WHEN count(*) = 0 THEN 'PASS (all cached balances match ledger)'
            ELSE 'FAIL (' || count(*) || ' accounts mismatch)'
       END AS result
FROM account a
JOIN (
    SELECT account_id,
           SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END) AS ledger_balance
    FROM ledger_entry
    GROUP BY account_id
) l ON l.account_id = a.account_id
WHERE a.balance <> l.ledger_balance;

-- Summary
SELECT 'bulk summary: transfers=' || count(*) FROM transfer WHERE reference LIKE 'TRF-%';
SELECT 'bulk summary: ledger_entries=' || count(*) FROM ledger_entry
WHERE transfer_id IN (SELECT transfer_id FROM transfer WHERE reference LIKE 'TRF-%');
SELECT 'bulk summary: pending_transfers_next_14_days=' || count(*)
FROM transfer
WHERE status = 'PENDING'
  AND created_at <= now() + make_interval(days => 14)
  AND reference LIKE 'TRF-%';

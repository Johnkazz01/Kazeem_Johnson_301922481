-- 01_transactions.sql
-- Transaction demos for Lagos Meridian Bank.
-- Demo 1: a committed funds transfer (debit + credit in one transaction).
-- Demo 2: a rolled-back funds transfer (nothing changes).
-- Demo 3: a SAVEPOINT recovery inside a bulk salary payment - one bad row is
--         skipped, the rest of the batch still commits.
-- Each demo prints a BEFORE / AFTER snapshot so the effect is visible.
-- The script cleans up after itself so it can be re-run.

SET timezone TO 'Africa/Lagos';

\echo '======================================================================'
\echo 'DEMO 1: COMMITTED funds transfer (account 2 -> account 3, 5000 NGN)'
\echo '======================================================================'

\echo '--- BEFORE: balances of account 2 and 3 ---'
SELECT account_id, account_number, balance
FROM account
WHERE account_id IN (2, 3)
ORDER BY account_id;

\echo '--- Executing the transfer inside one transaction ---'
BEGIN;

WITH new_transfer AS (
    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, currency, status, channel, narration)
    VALUES ('DEMO-COMMIT-01', 2, 3, 5000, 'NGN', 'SETTLED', 'BRANCH', 'Demo 1 committed transfer')
    RETURNING transfer_id, debit_account_id, credit_account_id, amount
)
INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
SELECT transfer_id, debit_account_id, 'DEBIT', amount, 'Demo 1 debit'
FROM new_transfer
UNION ALL
SELECT transfer_id, credit_account_id, 'CREDIT', amount, 'Demo 1 credit'
FROM new_transfer;

COMMIT;

\echo '--- AFTER: balances of account 2 and 3 ---'
SELECT account_id, account_number, balance
FROM account
WHERE account_id IN (2, 3)
ORDER BY account_id;

\echo '--- Cleanup demo 1 ---'
DELETE FROM ledger_entry WHERE transfer_id IN (SELECT transfer_id FROM transfer WHERE reference = 'DEMO-COMMIT-01');
DELETE FROM transfer WHERE reference = 'DEMO-COMMIT-01';
UPDATE account a SET balance = COALESCE(
    (SELECT SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END)
     FROM ledger_entry WHERE account_id = a.account_id), 0)
WHERE a.account_id IN (2, 3);

\echo '======================================================================'
\echo 'DEMO 2: ROLLED-BACK funds transfer (account 4 -> account 5, 7000 NGN)'
\echo '======================================================================'

\echo '--- BEFORE: balances of account 4 and 5 ---'
SELECT account_id, account_number, balance
FROM account
WHERE account_id IN (4, 5)
ORDER BY account_id;

\echo '--- Executing the transfer inside a transaction that will ROLLBACK ---'
BEGIN;

WITH new_transfer AS (
    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, currency, status, channel, narration)
    VALUES ('DEMO-ROLLBACK-01', 4, 5, 7000, 'NGN', 'SETTLED', 'BRANCH', 'Demo 2 rolled-back transfer')
    RETURNING transfer_id, debit_account_id, credit_account_id, amount
)
INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
SELECT transfer_id, debit_account_id, 'DEBIT', amount, 'Demo 2 debit'
FROM new_transfer
UNION ALL
SELECT transfer_id, credit_account_id, 'CREDIT', amount, 'Demo 2 credit'
FROM new_transfer;

\echo '--- ROLLBACK issued; nothing should persist ---'
ROLLBACK;

\echo '--- AFTER: balances of account 4 and 5 (unchanged) ---'
SELECT account_id, account_number, balance
FROM account
WHERE account_id IN (4, 5)
ORDER BY account_id;

\echo '--- Verify the rolled-back transfer is NOT in the table ---'
SELECT count(*) AS demo_rollback_rows FROM transfer WHERE reference = 'DEMO-ROLLBACK-01';

\echo '======================================================================'
\echo 'DEMO 3: SAVEPOINT recovery in a bulk salary payment'
\echo 'A corporate payroll account (11) pays 9 beneficiaries. One item has an'
\echo 'amount that exceeds the overdraft limit; the SAVEPOINT skips it while'
\echo 'the other 8 items still commit.'
\echo '======================================================================'

\echo '--- BEFORE: balance of payroll account 11 and bulk item statuses ---'
SELECT account_id, account_number, balance FROM account WHERE account_id = 11;

SELECT bulk_item_id, credit_account_id, beneficiary_name, amount, status
FROM bulk_payment_item
WHERE settlement_batch_id = (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001')
ORDER BY bulk_item_id;

\echo '--- Sabotage ONE item so the SAVEPOINT path is exercised ---'
-- Set the first item amount to 100,000,000 NGN which exceeds the corporate
-- overdraft limit of 5,000,000 NGN. The debit will fail inside the loop.
UPDATE bulk_payment_item
SET amount = 100000000, status = 'PENDING', failure_reason = NULL
WHERE bulk_item_id = (
    SELECT MIN(bulk_item_id)
    FROM bulk_payment_item
    WHERE settlement_batch_id = (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001')
);

-- Reset the rest to PENDING so the demo is re-runnable.
UPDATE bulk_payment_item
SET status = 'PENDING', failure_reason = NULL
WHERE settlement_batch_id = (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001');

\echo '--- Running the bulk salary loop with SAVEPOINT recovery ---'
DO $$
DECLARE
    item RECORD;
    v_transfer_id BIGINT;
    paid_count   INT := 0;
    failed_count INT := 0;
BEGIN
    FOR item IN
        SELECT bulk_item_id, debit_account_id, credit_account_id, beneficiary_name, amount
        FROM bulk_payment_item
        WHERE settlement_batch_id = (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001')
        ORDER BY bulk_item_id
    LOOP
        -- The inner BEGIN ... EXCEPTION block is the PL/pgSQL equivalent of a
        -- SAVEPOINT: if any statement inside fails, only this iteration's
        -- changes are rolled back and the loop continues with the next item.
        BEGIN
            INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, currency, status, channel, narration)
            VALUES ('BULK-PAY-' || item.bulk_item_id, item.debit_account_id, item.credit_account_id, item.amount, 'NGN', 'SETTLED', 'BULK', 'Salary: ' || item.beneficiary_name)
            RETURNING transfer_id INTO v_transfer_id;

            INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
            VALUES (v_transfer_id, item.debit_account_id, 'DEBIT', item.amount, 'Bulk salary debit');
            INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
            VALUES (v_transfer_id, item.credit_account_id, 'CREDIT', item.amount, 'Bulk salary credit');

            UPDATE bulk_payment_item SET status = 'PAID' WHERE bulk_item_id = item.bulk_item_id;
            paid_count := paid_count + 1;
        EXCEPTION WHEN OTHERS THEN
            -- SAVEPOINT recovery: the failed insert/update are undone; we mark
            -- the item FAILED and the loop continues.
            UPDATE bulk_payment_item
            SET status = 'FAILED', failure_reason = left(SQLERRM, 160)
            WHERE bulk_item_id = item.bulk_item_id;
            failed_count := failed_count + 1;
        END;
    END LOOP;

    RAISE NOTICE 'Bulk salary run complete: % paid, % failed', paid_count, failed_count;
END $$;

\echo '--- AFTER: balance of payroll account 11 and bulk item statuses ---'
SELECT account_id, account_number, balance FROM account WHERE account_id = 11;

SELECT bulk_item_id, credit_account_id, beneficiary_name, amount, status, failure_reason
FROM bulk_payment_item
WHERE settlement_batch_id = (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001')
ORDER BY bulk_item_id;

\echo '--- Cleanup demo 3: undo all bulk salary transfers and reset items ---'
DELETE FROM ledger_entry WHERE transfer_id IN (SELECT transfer_id FROM transfer WHERE reference LIKE 'BULK-PAY-%');
DELETE FROM transfer WHERE reference LIKE 'BULK-PAY-%';

UPDATE bulk_payment_item
SET status = 'PENDING', failure_reason = NULL,
    amount = CASE beneficiary_name
        WHEN 'Chinedu Okafor'  THEN 250000.00
        WHEN 'Ngozi Eze'       THEN 180000.00
        WHEN 'Tunde Bakare'    THEN 220000.00
        WHEN 'Fatima Bello'    THEN 150000.00
        WHEN 'Emeka Nwosu'     THEN 300000.00
        WHEN 'Aisha Mohammed'  THEN 175000.00
        WHEN 'Funke Adebayo'   THEN 200000.00
        WHEN 'Ibrahim Musa'    THEN 165000.00
        WHEN 'Zainab Yusuf'    THEN 140000.00
        ELSE amount
    END
WHERE settlement_batch_id = (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001');

-- Recompute cached balances from the ledger for every affected account.
UPDATE account a SET balance = COALESCE(
    (SELECT SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END)
     FROM ledger_entry WHERE account_id = a.account_id), 0)
WHERE a.account_id IN (
    SELECT DISTINCT account_id FROM ledger_entry
    UNION SELECT 11
);

\echo '--- Verify cleanup: no demo transfers remain ---'
SELECT count(*) AS demo_rows_remaining FROM transfer
WHERE reference LIKE 'DEMO-%' OR reference LIKE 'BULK-PAY-%';

\echo '=== 01_transactions.sql complete ==='

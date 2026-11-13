-- 05_constraint_tests.sql
-- Constraint and trigger tests for Lagos Meridian Bank schema.
-- 10 tests that must FAIL on the intended constraint, each inside BEGIN ... ROLLBACK
-- and each building its own data. 1 control test that must SUCCEED.
-- Each test prints PASS or FAIL with the constraint name and the error message.

SET timezone TO 'Africa/Lagos';

\echo '=== Constraint tests for Lagos Meridian Bank ==='

-- ----------------------------------------------------------------------
-- Test 1: CHECK customer.customer_type must be INDIVIDUAL or CORPORATE
-- ----------------------------------------------------------------------
BEGIN;
DO $$
BEGIN
    INSERT INTO customer (customer_type, full_name, bvn, email, phone, state)
    VALUES ('GOVERNMENT', 'Test Government Body', '99999999999', 'gov@test.ng', '08099999999', 'Lagos');
    RAISE NOTICE 'FAIL: customer_type_check - violation was not caught';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: customer_type_check - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 2: UNIQUE customer.bvn
-- ----------------------------------------------------------------------
BEGIN;
DO $$
BEGIN
    INSERT INTO customer (customer_type, full_name, bvn, email, phone, state)
    VALUES ('INDIVIDUAL', 'Duplicate BVN Holder', '22123456701', 'dup@test.ng', '08099999998', 'Lagos');
    RAISE NOTICE 'FAIL: unique_bvn - violation was not caught';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: unique_bvn - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 3: FK account.customer_id must reference an existing customer
-- ----------------------------------------------------------------------
BEGIN;
DO $$
BEGIN
    INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, status)
    VALUES ('TEST-FK-01', 99999, 1, 1, 'NGN', CURRENT_DATE, 'ACTIVE');
    RAISE NOTICE 'FAIL: fk_account_customer - violation was not caught';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'PASS: fk_account_customer - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 4: CHECK transfer.amount must be > 0
-- ----------------------------------------------------------------------
BEGIN;
DO $$
BEGIN
    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-AMT-01', 2, 3, -100, 'SETTLED', 'BRANCH');
    RAISE NOTICE 'FAIL: transfer_amount_positive - violation was not caught';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: transfer_amount_positive - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 5: CHECK transfer.debit_account_id <> credit_account_id
-- ----------------------------------------------------------------------
BEGIN;
DO $$
BEGIN
    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-SELF-01', 2, 2, 100, 'SETTLED', 'BRANCH');
    RAISE NOTICE 'FAIL: transfer_self_transfer - violation was not caught';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: transfer_self_transfer - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 6: Trigger - a CLOSED account cannot transact
-- ----------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    acct_id BIGINT;
    v_tid BIGINT;
BEGIN
    INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, status)
    VALUES ('9000000001', 2, 1, 2, 'NGN', CURRENT_DATE, 'CLOSED')
    RETURNING account_id INTO acct_id;

    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-CLOSED-TRF-01', acct_id, 3, 100, 'SETTLED', 'BRANCH')
    RETURNING transfer_id INTO v_tid;

    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, acct_id, 'DEBIT', 100);

    RAISE NOTICE 'FAIL: closed_account_no_transact - trigger did not fire';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: closed_account_no_transact - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 7: Trigger - a FROZEN account cannot transact
-- ----------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    acct_id BIGINT;
    v_tid BIGINT;
BEGIN
    INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, status)
    VALUES ('9000000002', 2, 1, 2, 'NGN', CURRENT_DATE, 'FROZEN')
    RETURNING account_id INTO acct_id;

    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-FROZEN-TRF-01', acct_id, 3, 100, 'SETTLED', 'BRANCH')
    RETURNING transfer_id INTO v_tid;

    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, acct_id, 'DEBIT', 100);

    RAISE NOTICE 'FAIL: frozen_account_no_transact - trigger did not fire';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: frozen_account_no_transact - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 8: Trigger - a debit cannot take a non-overdraft (savings) account below zero
-- ----------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    acct_id BIGINT;
    v_tid BIGINT;
BEGIN
    -- Savings account, balance 0, no overdraft
    INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, balance, overdraft_limit, status)
    VALUES ('9000000003', 2, 1, 1, 'NGN', CURRENT_DATE, 0, 0, 'ACTIVE')
    RETURNING account_id INTO acct_id;

    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-SAV-TRF-01', acct_id, 3, 1000, 'SETTLED', 'BRANCH')
    RETURNING transfer_id INTO v_tid;

    -- Debit of 1000 on a 0-balance savings account must be rejected
    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, acct_id, 'DEBIT', 1000);

    RAISE NOTICE 'FAIL: debit_below_zero - trigger did not fire';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: debit_below_zero - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 9: Trigger - every transfer must have balanced debit and credit ledger entries
-- Insert two debits and no credit for the same transfer (uses the capital account
-- which allows overdraft so the balance check does not pre-empt the balanced check).
-- ----------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    v_tid BIGINT;
BEGIN
    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-BAL-TRF-01', 1, 2, 100, 'SETTLED', 'BRANCH')
    RETURNING transfer_id INTO v_tid;

    -- First debit: entry_count = 1, balanced check skips
    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, 1, 'DEBIT', 100);

    -- Second debit: entry_count = 2, debits=200 credits=0, imbalance
    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, 1, 'DEBIT', 100);

    RAISE NOTICE 'FAIL: balanced_debit_credit - trigger did not fire';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: balanced_debit_credit - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Test 10: Partial UNIQUE index - one ACTIVE standing order per
-- (debit account, credit account, purpose)
-- ----------------------------------------------------------------------
BEGIN;
DO $$
BEGIN
    INSERT INTO standing_order (debit_account_id, credit_account_id, amount, currency, purpose, frequency, next_run_date, end_date, status)
    VALUES (2, 3, 5000, 'NGN', 'TEST-DUP', 'MONTHLY', CURRENT_DATE + 10, DATE '2027-12-31', 'ACTIVE');

    -- Duplicate ACTIVE standing order with the same (debit, credit, purpose)
    INSERT INTO standing_order (debit_account_id, credit_account_id, amount, currency, purpose, frequency, next_run_date, end_date, status)
    VALUES (2, 3, 7000, 'NGN', 'TEST-DUP', 'MONTHLY', CURRENT_DATE + 20, DATE '2027-12-31', 'ACTIVE');

    RAISE NOTICE 'FAIL: partial_unique_standing_order - violation was not caught';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: partial_unique_standing_order - %', SQLERRM;
END $$;
ROLLBACK;

-- ----------------------------------------------------------------------
-- Control test: a valid balanced transfer MUST succeed
-- ----------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    acct_id BIGINT;
    v_tid BIGINT;
BEGIN
    -- Savings account seeded with enough balance
    INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, balance, overdraft_limit, status)
    VALUES ('9000000004', 2, 1, 1, 'NGN', CURRENT_DATE, 10000, 0, 'ACTIVE')
    RETURNING account_id INTO acct_id;

    INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
    VALUES ('TEST-CTRL-TRF-01', acct_id, 3, 1000, 'SETTLED', 'BRANCH')
    RETURNING transfer_id INTO v_tid;

    -- Balanced debit + credit
    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, acct_id, 'DEBIT', 1000);
    INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
    VALUES (v_tid, 3, 'CREDIT', 1000);

    RAISE NOTICE 'PASS: control_valid_transfer - balanced 1000 NGN transfer posted successfully';
END $$;
ROLLBACK;

\echo '=== Constraint tests complete ==='

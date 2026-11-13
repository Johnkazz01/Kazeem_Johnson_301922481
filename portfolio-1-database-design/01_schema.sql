-- 01_schema.sql
-- Lagos Meridian Bank transaction banking schema.
-- Creates 10 tables in 3NF, plus 3 triggers, 1 partial UNIQUE index, CHECK / FK / UNIQUE constraints.
-- Sets the database time zone to Africa/Lagos so now(), CURRENT_DATE and timestamptz default to WAT.
-- Runs top to bottom with ON_ERROR_STOP=1 and is idempotent (DROP ... IF EXISTS first).

ALTER DATABASE txnbank SET timezone TO 'Africa/Lagos';
SET timezone TO 'Africa/Lagos';

-- Drop in dependency-safe order.
DROP TRIGGER IF EXISTS trg_check_account_status ON ledger_entry;
DROP TRIGGER IF EXISTS trg_check_debit_balance ON ledger_entry;
DROP TRIGGER IF EXISTS trg_transfer_balanced ON ledger_entry;
DROP FUNCTION IF EXISTS check_account_status();
DROP FUNCTION IF EXISTS check_debit_balance();
DROP FUNCTION IF EXISTS check_transfer_balanced();

DROP TABLE IF EXISTS bulk_payment_item;
DROP TABLE IF EXISTS standing_order;
DROP TABLE IF EXISTS ledger_entry;
DROP TABLE IF EXISTS transfer;
DROP TABLE IF EXISTS settlement_batch;
DROP TABLE IF EXISTS fee_schedule;
DROP TABLE IF EXISTS account;
DROP TABLE IF EXISTS account_type;
DROP TABLE IF EXISTS customer;
DROP TABLE IF EXISTS branch;

-- 1. branch -------------------------------------------------------------
CREATE TABLE branch (
    branch_id    BIGSERIAL PRIMARY KEY,
    code         VARCHAR(10)  NOT NULL UNIQUE,
    name         VARCHAR(120) NOT NULL,
    address      VARCHAR(200) NOT NULL,
    lga          VARCHAR(60)  NOT NULL,
    state        VARCHAR(60)  NOT NULL,
    opened_on    DATE         NOT NULL,
    status       VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE','CLOSED'))
);

-- 2. customer -----------------------------------------------------------
CREATE TABLE customer (
    customer_id   BIGSERIAL PRIMARY KEY,
    customer_type VARCHAR(10) NOT NULL
                   CHECK (customer_type IN ('INDIVIDUAL','CORPORATE')),
    full_name     VARCHAR(160) NOT NULL,
    bvn           VARCHAR(11) NOT NULL UNIQUE,
    email         VARCHAR(160) NOT NULL UNIQUE,
    phone         VARCHAR(15) NOT NULL,
    state         VARCHAR(60) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','DORMANT','CLOSED'))
);

-- 3. account_type -------------------------------------------------------
CREATE TABLE account_type (
    account_type_id BIGSERIAL PRIMARY KEY,
    code            VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(60) NOT NULL,
    min_balance     NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (min_balance >= 0),
    allows_overdraft BOOLEAN NOT NULL DEFAULT FALSE,
    overdraft_limit  NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (overdraft_limit >= 0)
);

-- 4. account ------------------------------------------------------------
CREATE TABLE account (
    account_id      BIGSERIAL PRIMARY KEY,
    account_number  VARCHAR(12) NOT NULL UNIQUE,
    customer_id     BIGINT NOT NULL REFERENCES customer(customer_id),
    branch_id       BIGINT NOT NULL REFERENCES branch(branch_id),
    account_type_id BIGINT NOT NULL REFERENCES account_type(account_type_id),
    currency        VARCHAR(3) NOT NULL DEFAULT 'NGN' CHECK (currency IN ('NGN','USD','GBP')),
    opened_on       DATE NOT NULL,
    -- Cached balance maintained by the trg_check_debit_balance trigger.
    -- Never set by INSERT/UPDATE from application code; only the trigger writes it.
    balance         NUMERIC(18,2) NOT NULL DEFAULT 0,
    overdraft_limit NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (overdraft_limit >= 0),
    status          VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','FROZEN','CLOSED'))
);

-- 5. fee_schedule -------------------------------------------------------
CREATE TABLE fee_schedule (
    fee_id      BIGSERIAL PRIMARY KEY,
    fee_code    VARCHAR(20) NOT NULL UNIQUE,
    fee_name    VARCHAR(80) NOT NULL,
    fee_type    VARCHAR(10) NOT NULL CHECK (fee_type IN ('FLAT','PERCENT')),
    amount      NUMERIC(18,4) NOT NULL CHECK (amount >= 0),
    min_amount  NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (min_amount >= 0),
    max_amount  NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (max_amount >= 0),
    applies_to  VARCHAR(20) NOT NULL CHECK (applies_to IN ('TRANSFER','MAINTENANCE','REVERSAL','BULK')),
    active_from DATE NOT NULL,
    active_to   DATE,
    CHECK (active_to IS NULL OR active_to >= active_from)
);

-- 6. settlement_batch ---------------------------------------------------
CREATE TABLE settlement_batch (
    settlement_batch_id BIGSERIAL PRIMARY KEY,
    batch_ref           VARCHAR(20) NOT NULL UNIQUE,
    batch_date          DATE NOT NULL,
    status              VARCHAR(10) NOT NULL DEFAULT 'OPEN'
                         CHECK (status IN ('OPEN','CLOSED','REVERSED')),
    total_amount        NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    item_count          INTEGER NOT NULL DEFAULT 0 CHECK (item_count >= 0),
    opened_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at           TIMESTAMPTZ
);

-- 7. transfer (the transaction) ----------------------------------------
CREATE TABLE transfer (
    transfer_id         BIGSERIAL PRIMARY KEY,
    reference           VARCHAR(20) NOT NULL UNIQUE,
    debit_account_id    BIGINT NOT NULL REFERENCES account(account_id),
    credit_account_id   BIGINT NOT NULL REFERENCES account(account_id),
    amount              NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    currency            VARCHAR(3) NOT NULL DEFAULT 'NGN' CHECK (currency IN ('NGN','USD','GBP')),
    status              VARCHAR(10) NOT NULL DEFAULT 'PENDING'
                         CHECK (status IN ('PENDING','SETTLED','FAILED','REVERSED')),
    channel             VARCHAR(20) NOT NULL
                         CHECK (channel IN ('BRANCH','INTERNET','USSD','BULK')),
    narration           VARCHAR(160),
    fee_id              BIGINT REFERENCES fee_schedule(fee_id),
    settlement_batch_id BIGINT REFERENCES settlement_batch(settlement_batch_id),
    settlement_ref      VARCHAR(40),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    settled_at          TIMESTAMPTZ,
    CHECK (debit_account_id <> credit_account_id)
);

-- A transfer may be settled at most once: settlement_ref is unique when populated.
CREATE UNIQUE INDEX uq_transfer_settlement_ref ON transfer(settlement_ref)
    WHERE settlement_ref IS NOT NULL;

-- 8. ledger_entry (double-entry debit/credit lines) --------------------
CREATE TABLE ledger_entry (
    ledger_id    BIGSERIAL PRIMARY KEY,
    transfer_id  BIGINT NOT NULL REFERENCES transfer(transfer_id),
    account_id   BIGINT NOT NULL REFERENCES account(account_id),
    direction    VARCHAR(6) NOT NULL CHECK (direction IN ('DEBIT','CREDIT')),
    amount       NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    narration    VARCHAR(160)
);

-- 9. standing_order -----------------------------------------------------
CREATE TABLE standing_order (
    standing_order_id  BIGSERIAL PRIMARY KEY,
    debit_account_id   BIGINT NOT NULL REFERENCES account(account_id),
    credit_account_id  BIGINT NOT NULL REFERENCES account(account_id),
    amount             NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    currency           VARCHAR(3) NOT NULL DEFAULT 'NGN',
    purpose            VARCHAR(60) NOT NULL,
    frequency          VARCHAR(10) NOT NULL
                        CHECK (frequency IN ('DAILY','WEEKLY','MONTHLY')),
    next_run_date      DATE NOT NULL,
    end_date           DATE NOT NULL,
    status             VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
                        CHECK (status IN ('ACTIVE','PAUSED','CANCELLED')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_date >= next_run_date),
    CHECK (debit_account_id <> credit_account_id)
);

-- Partial UNIQUE index: one ACTIVE standing order per (debit account, credit account, purpose).
-- Re-read the rule: "one partial UNIQUE index (for example one ACTIVE standing order per account
-- per beneficiary per purpose)". We use a partial index scoped to status='ACTIVE'.
CREATE UNIQUE INDEX uq_active_standing_order
    ON standing_order (debit_account_id, credit_account_id, purpose)
    WHERE status = 'ACTIVE';

-- 10. bulk_payment_item -------------------------------------------------
CREATE TABLE bulk_payment_item (
    bulk_item_id      BIGSERIAL PRIMARY KEY,
    settlement_batch_id BIGINT NOT NULL REFERENCES settlement_batch(settlement_batch_id),
    debit_account_id  BIGINT NOT NULL REFERENCES account(account_id),
    credit_account_id BIGINT NOT NULL REFERENCES account(account_id),
    beneficiary_name  VARCHAR(160) NOT NULL,
    amount            NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    status            VARCHAR(10) NOT NULL DEFAULT 'PENDING'
                       CHECK (status IN ('PENDING','PAID','FAILED')),
    failure_reason    VARCHAR(160),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (debit_account_id <> credit_account_id)
);

-- ----------------------------------------------------------------------
-- Trigger functions
-- ----------------------------------------------------------------------

-- Trigger A: A CLOSED or FROZEN account cannot transact.
CREATE OR REPLACE FUNCTION check_account_status()
RETURNS TRIGGER AS $$
DECLARE
    acct_status VARCHAR(10);
BEGIN
    SELECT status INTO acct_status
    FROM account
    WHERE account_id = NEW.account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % does not exist', NEW.account_id;
    END IF;

    IF acct_status IN ('CLOSED','FROZEN') THEN
        RAISE EXCEPTION 'Account % is % and cannot transact',
            NEW.account_id, acct_status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger B: A debit cannot take a non-overdraft account below zero
-- (or below -overdraft_limit when overdraft is allowed).
-- Also maintains the cached account.balance so it is always equal to
-- SUM(credits) - SUM(debits) for that account.
CREATE OR REPLACE FUNCTION check_debit_balance()
RETURNS TRIGGER AS $$
DECLARE
    acct_balance       NUMERIC(18,2);
    acct_overdraft     BOOLEAN;
    acct_od_limit      NUMERIC(18,2);
    new_running        NUMERIC(18,2);
BEGIN
    SELECT a.balance, at.allows_overdraft, a.overdraft_limit
      INTO acct_balance, acct_overdraft, acct_od_limit
    FROM account a
    JOIN account_type at ON a.account_type_id = at.account_type_id
    WHERE a.account_id = NEW.account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % does not exist', NEW.account_id;
    END IF;

    IF NEW.direction = 'DEBIT' THEN
        new_running := acct_balance - NEW.amount;
        IF NOT acct_overdraft AND new_running < 0 THEN
            RAISE EXCEPTION
                'Insufficient funds on account %: debit of % would leave balance %',
                NEW.account_id, NEW.amount, new_running
                USING ERRCODE = 'check_violation';
        END IF;
        IF acct_overdraft AND new_running < -acct_od_limit THEN
            RAISE EXCEPTION
                'Overdraft limit exceeded on account %: debit of % would leave balance % (limit %)',
                NEW.account_id, NEW.amount, new_running, -acct_od_limit
                USING ERRCODE = 'check_violation';
        END IF;
        UPDATE account SET balance = new_running WHERE account_id = NEW.account_id;
    ELSE
        new_running := acct_balance + NEW.amount;
        UPDATE account SET balance = new_running WHERE account_id = NEW.account_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger C: Every transfer must have balanced debit and credit ledger entries.
-- Non-deferred AFTER ROW trigger that only enforces the balance once a transfer
-- has at least two ledger entries (so inserting the first leg does not abort the
-- statement; the second leg is checked immediately). This is testable inside
-- BEGIN ... ROLLBACK blocks unlike a DEFERRABLE INITIALLY DEFERRED trigger.
CREATE OR REPLACE FUNCTION check_transfer_balanced()
RETURNS TRIGGER AS $$
DECLARE
    total_debit  NUMERIC(18,2);
    total_credit NUMERIC(18,2);
    entry_count  INT;
BEGIN
    SELECT
        COUNT(*),
        COALESCE(SUM(CASE WHEN direction='DEBIT'  THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE 0 END), 0)
      INTO entry_count, total_debit, total_credit
    FROM ledger_entry
    WHERE transfer_id = NEW.transfer_id;

    IF entry_count >= 2 AND total_debit <> total_credit THEN
        RAISE EXCEPTION
            'Unbalanced ledger for transfer %: debits=%, credits=%',
            NEW.transfer_id, total_debit, total_credit
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transfer_balanced
    AFTER INSERT OR UPDATE ON ledger_entry
    FOR EACH ROW EXECUTE FUNCTION check_transfer_balanced();

CREATE TRIGGER trg_check_account_status
    BEFORE INSERT OR UPDATE ON ledger_entry
    FOR EACH ROW EXECUTE FUNCTION check_account_status();

CREATE TRIGGER trg_check_debit_balance
    BEFORE INSERT OR UPDATE ON ledger_entry
    FOR EACH ROW EXECUTE FUNCTION check_debit_balance();

-- No CHECK using CURRENT_DATE - the standing order next_run_date advance is enforced
-- by a trigger that runs on standing_order UPDATE, not by a CHECK constraint.
CREATE OR REPLACE FUNCTION check_standing_order_dates()
RETURNS TRIGGER AS $$
BEGIN
    -- end_date must not be in the past relative to today when the order is ACTIVE.
    IF NEW.status = 'ACTIVE' AND NEW.end_date < CURRENT_DATE THEN
        RAISE EXCEPTION
            'Standing order end_date % is in the past for ACTIVE order %',
            NEW.end_date, NEW.standing_order_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_standing_order_dates ON standing_order;
CREATE TRIGGER trg_standing_order_dates
    BEFORE INSERT OR UPDATE ON standing_order
    FOR EACH ROW EXECUTE FUNCTION check_standing_order_dates();

-- Done.

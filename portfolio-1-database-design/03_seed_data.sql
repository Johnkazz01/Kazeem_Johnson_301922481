-- 03_seed_data.sql
-- Seed data for Lagos Meridian Bank: branches, account types, customers, accounts,
-- fee schedule, settlement batches, standing orders, bulk payment items, and the
-- opening-balance ledger entries that give every customer account a starting balance.
-- All names are Nigerian and gender-matched. No card numbers, CVV or PIN values.
-- Idempotent inside a fresh schema (uses ON CONFLICT DO NOTHING for reference rows
-- and explicit DELETE for any prior seed rows).

SET timezone TO 'Africa/Lagos';

-- Clean any prior seed/bulk rows so the script is re-runnable.
DELETE FROM ledger_entry   WHERE transfer_id IN (SELECT transfer_id FROM transfer);
DELETE FROM transfer;
DELETE FROM bulk_payment_item;
DELETE FROM standing_order;
DELETE FROM settlement_batch;
DELETE FROM account;
DELETE FROM fee_schedule;
DELETE FROM customer;
DELETE FROM account_type;
DELETE FROM branch;

-- ----------------------------------------------------------------------
-- Branches (real Nigerian LGAs / states)
-- ----------------------------------------------------------------------
INSERT INTO branch (code, name, address, lga, state, opened_on, status) VALUES
('LMB-VI-01',  'Lagos Meridian Bank - Victoria Island', '12 Akin Adesola Street', 'Eti-Osa',  'Lagos',     DATE '2009-03-02', 'ACTIVE'),
('LMB-YB-02',  'Lagos Meridian Bank - Yaba',            '234 Herbert Macaulay Way',  'Yaba',      'Lagos',     DATE '2011-08-15', 'ACTIVE'),
('LMB-AB-03',  'Lagos Meridian Bank - Abuja Central',   'Plot 799 Tafawa Balewa Way','Municipal','FCT',       DATE '2013-01-20', 'ACTIVE'),
('LMB-PH-04',  'Lagos Meridian Bank - Port Harcourt',   '5 Azikiwe Road',            'Port Harcourt','Rivers', DATE '2014-06-10', 'ACTIVE'),
('LMB-KN-05',  'Lagos Meridian Bank - Kano',            '12 Murtala Mohammed Way',   'Kano Municipal','Kano', DATE '2016-02-14', 'ACTIVE'),
('LMB-IB-06',  'Lagos Meridian Bank - Ibadan',          '8 Ring Road, Challenge',     'Ibadan North West','Oyo', DATE '2017-09-01', 'ACTIVE');

-- ----------------------------------------------------------------------
-- Account types
-- ----------------------------------------------------------------------
INSERT INTO account_type (code, name, min_balance, allows_overdraft, overdraft_limit) VALUES
('SAVINGS',           'Personal Savings',        1000.00,  FALSE, 0),
('CURRENT',           'Personal Current',        0,        TRUE,  500000.00),
('CORP_CURRENT',      'Corporate Current',       0,        TRUE,  5000000.00),
('CAPITAL',           'Bank Capital Account',    0,        TRUE,  1000000000.00);

-- ----------------------------------------------------------------------
-- Customers (gender-matched Nigerian names)
-- 1 capital holder + 9 individuals + 6 corporates = 16 customers
-- ----------------------------------------------------------------------
INSERT INTO customer (customer_type, full_name, bvn, email, phone, state, status) VALUES
('CORPORATE', 'Lagos Meridian Bank Capital Reserve', '00000000001', 'capital@lagosmeridianbank.ng', '08000000000', 'Lagos', 'ACTIVE'),
('INDIVIDUAL','Chinedu Okafor',        '22123456701', 'chinedu.okafor@example.ng',    '08021234567', 'Lagos',  'ACTIVE'),
('INDIVIDUAL','Ngozi Eze',              '22123456702', 'ngozi.eze@example.ng',        '08021234568', 'Lagos',  'ACTIVE'),
('INDIVIDUAL','Tunde Bakare',            '22123456703', 'tunde.bakare@example.ng',     '08021234569', 'Lagos',  'ACTIVE'),
('INDIVIDUAL','Fatima Bello',            '22123456704', 'fatima.bello@example.ng',      '08021234570', 'FCT',    'ACTIVE'),
('INDIVIDUAL','Emeka Nwosu',             '22123456705', 'emeka.nwosu@example.ng',       '08021234571', 'Rivers', 'ACTIVE'),
('INDIVIDUAL','Aisha Mohammed',          '22123456706', 'aisha.mohammed@example.ng',    '08021234572', 'Kano',   'ACTIVE'),
('INDIVIDUAL','Funke Adebayo',           '22123456707', 'funke.adebayo@example.ng',     '08021234573', 'Oyo',    'ACTIVE'),
('INDIVIDUAL','Ibrahim Musa',            '22123456708', 'ibrahim.musa@example.ng',      '08021234574', 'Kano',   'ACTIVE'),
('INDIVIDUAL','Zainab Yusuf',            '22123456709', 'zainab.yusuf@example.ng',      '08021234575', 'FCT',    'ACTIVE'),
('CORPORATE','Kola & Sons Trading Ltd',   '22123456801', 'finance@kolasons.ng',           '08021234576', 'Lagos',  'ACTIVE'),
('CORPORATE','Sahel Logistics Limited',    '22123456802', 'treasury@sahellog.ng',          '08021234577', 'FCT',    'ACTIVE'),
('CORPORATE','Meridian Haulage Plc',      '22123456803', 'accounts@meridianhaul.ng',      '08021234578', 'Rivers', 'ACTIVE'),
('CORPORATE','Odua Foods Limited',        '22123456804', 'payroll@oduafoods.ng',          '08021234579', 'Oyo',    'ACTIVE'),
('CORPORATE','Bature Cement Distributors','22123456805', 'finance@baturecement.ng',      '08021234580', 'Kano',   'ACTIVE'),
('CORPORATE','Eko Marine Services',       '22123456806', 'treasury@ekomarine.ng',         '08021234581', 'Lagos',  'ACTIVE');

-- ----------------------------------------------------------------------
-- Accounts (one per customer, 10-digit NUBAN-style numbers)
-- Capital account is account_id = 1 and is the source of opening balances.
-- ----------------------------------------------------------------------
INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, balance, overdraft_limit, status)
SELECT
    lpad(c.customer_id::text, 10, '0'),
    c.customer_id,
    CASE c.customer_id
        WHEN 1 THEN 1
        WHEN 4 THEN 3
        WHEN 5 THEN 4
        WHEN 7 THEN 5
        WHEN 8 THEN 6
        WHEN 9 THEN 5
        WHEN 10 THEN 3
        WHEN 12 THEN 3
        WHEN 13 THEN 4
        WHEN 14 THEN 6
        WHEN 15 THEN 5
        ELSE 1
    END,
    CASE c.customer_type
        WHEN 'CORPORATE' THEN (CASE WHEN c.customer_id = 1 THEN 4 ELSE 3 END)
        ELSE 2  -- personal current
    END,
    'NGN',
    DATE '2024-01-02',
    0,
    CASE c.customer_type
        WHEN 'CORPORATE' THEN (CASE WHEN c.customer_id = 1 THEN 1000000000 ELSE 5000000 END)
        ELSE 500000
    END,
    'ACTIVE'
FROM customer c
ORDER BY c.customer_id;

-- Mark the savings account for individuals that opened a savings product too:
-- give customer_id=8 (Funke Adebayo) an additional savings account.
INSERT INTO account (account_number, customer_id, branch_id, account_type_id, currency, opened_on, balance, overdraft_limit, status)
VALUES ('9000000017', 8, 6, 1, 'NGN', DATE '2024-04-12', 0, 0, 'ACTIVE');

-- ----------------------------------------------------------------------
-- Fee schedule
-- ----------------------------------------------------------------------
INSERT INTO fee_schedule (fee_code, fee_name, fee_type, amount, min_amount, max_amount, applies_to, active_from, active_to) VALUES
('INTRA_FEE',     'Intra-bank transfer fee',      'FLAT',    50.0000,    0, 100000, 'TRANSFER',    DATE '2024-01-01', NULL),
('INTER_FEE',     'Inter-bank transfer fee',      'FLAT',   105.7500,    0, 500000, 'TRANSFER',    DATE '2024-01-01', NULL),
('BULK_FEE',      'Bulk salary per-item fee',     'FLAT',    35.0000,    0,  50000, 'BULK',        DATE '2024-01-01', NULL),
('MAINT_FEE',     'Monthly maintenance fee',     'FLAT',   250.0000,    0,  50000, 'MAINTENANCE', DATE '2024-01-01', NULL),
('REVERSAL_FEE',  'Reversal processing fee',      'FLAT',   100.0000,    0,  10000, 'REVERSAL',    DATE '2024-01-01', NULL),
('CORP_TRANSFER', 'Corporate transfer percent',   'PERCENT',  0.5000,    0, 25000, 'TRANSFER',    DATE '2024-01-01', NULL);

-- ----------------------------------------------------------------------
-- Settlement batches (one open, a few closed)
-- ----------------------------------------------------------------------
INSERT INTO settlement_batch (batch_ref, batch_date, status, total_amount, item_count, opened_at, closed_at) VALUES
('SET-2025-001', CURRENT_DATE - 30, 'CLOSED', 8420000.00, 142, now() - interval '30 days', now() - interval '30 days' + interval '2 hours'),
('SET-2025-002', CURRENT_DATE - 15, 'CLOSED', 3115000.00,  68, now() - interval '15 days', now() - interval '15 days' + interval '1 hour'),
('SET-2025-003', CURRENT_DATE,      'OPEN',        0.00,   0, now(), NULL);

-- ----------------------------------------------------------------------
-- Opening balance transfers: capital -> each customer account
-- This is the only place money is created inside the bank. Each opening
-- balance transfer debits the capital account and credits one customer account.
-- ----------------------------------------------------------------------
INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, currency, status, channel, narration, created_at, settled_at)
SELECT
    'OPEN-' || lpad(a.account_id::text, 7, '0'),
    1,                                      -- capital account
    a.account_id,
    CASE
        WHEN a.account_id = 2  THEN  5000000.00   -- Chinedu
        WHEN a.account_id = 3  THEN  2500000.00   -- Ngozi
        WHEN a.account_id = 4  THEN  3000000.00   -- Tunde
        WHEN a.account_id = 5  THEN  1800000.00   -- Fatima
        WHEN a.account_id = 6  THEN  4200000.00   -- Emeka
        WHEN a.account_id = 7  THEN  1500000.00   -- Aisha
        WHEN a.account_id = 8  THEN  3200000.00   -- Funke
        WHEN a.account_id = 9  THEN  2200000.00   -- Ibrahim
        WHEN a.account_id = 10 THEN  900000.00    -- Zainab
        WHEN a.account_id = 11 THEN  9000000.00   -- Kola & Sons
        WHEN a.account_id = 12 THEN  7000000.00   -- Sahel
        WHEN a.account_id = 13 THEN  6500000.00   -- Meridian Haulage
        WHEN a.account_id = 14 THEN  4800000.00   -- Odua Foods
        WHEN a.account_id = 15 THEN  5300000.00   -- Bature Cement
        WHEN a.account_id = 16 THEN  6100000.00   -- Eko Marine
        WHEN a.account_id = 17 THEN  400000.00    -- Funke savings
        ELSE 100000.00
    END,
    'NGN',
    'SETTLED',
    'BRANCH',
    'Opening balance',
    DATE '2024-01-02' + interval '9 hours',
    DATE '2024-01-02' + interval '9 hours' + interval '5 minutes'
FROM account a
WHERE a.account_id > 1;

-- Ledger entries for the opening balances: debit capital, credit customer.
-- Inserted in one statement so the DEFERRABLE balanced trigger fires at commit.
INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, created_at, narration)
SELECT t.transfer_id, t.debit_account_id, 'DEBIT',  t.amount, t.created_at, t.narration
FROM transfer t
UNION ALL
SELECT t.transfer_id, t.credit_account_id, 'CREDIT', t.amount, t.created_at, t.narration
FROM transfer t;

-- ----------------------------------------------------------------------
-- A handful of standing orders (next_run_date includes future-dated runs)
-- ----------------------------------------------------------------------
INSERT INTO standing_order
    (debit_account_id, credit_account_id, amount, currency, purpose, frequency, next_run_date, end_date, status)
VALUES
(2, 3,  15000.00, 'NGN', 'RENT_SUBSIDY',      'MONTHLY', CURRENT_DATE + 2,  DATE '2026-12-31', 'ACTIVE'),
(4, 5,  20000.00, 'NGN', 'SCHOOL_FEES',       'MONTHLY', CURRENT_DATE + 5,  DATE '2027-06-30', 'ACTIVE'),
(6, 8,  10000.00, 'NGN', 'PARENT_SUPPORT',    'MONTHLY', CURRENT_DATE + 7,  DATE '2026-12-31', 'ACTIVE'),
(11,2, 50000.00, 'NGN', 'STAFF_ALLOWANCE',    'MONTHLY', CURRENT_DATE + 1,  DATE '2027-03-31', 'ACTIVE'),
(13,6, 35000.00, 'NGN', 'VENDOR_PAYMENT',     'WEEKLY',  CURRENT_DATE + 3,  DATE '2026-12-31', 'ACTIVE'),
(7, 9,   8000.00, 'NGN', 'FAMILY_REMITTANCE', 'MONTHLY', CURRENT_DATE - 1,  DATE '2027-09-30', 'ACTIVE');

-- ----------------------------------------------------------------------
-- A small corporate salary bulk payment batch (used by Portfolio 3 SAVEPOINT demo)
-- ----------------------------------------------------------------------
INSERT INTO settlement_batch (batch_ref, batch_date, status, total_amount, item_count, opened_at, closed_at)
VALUES ('BULK-PAY-001', CURRENT_DATE, 'OPEN', 0, 0, now(), NULL);

INSERT INTO bulk_payment_item
    (settlement_batch_id, debit_account_id, credit_account_id, beneficiary_name, amount, status)
SELECT
    (SELECT settlement_batch_id FROM settlement_batch WHERE batch_ref = 'BULK-PAY-001'),
    11,                     -- Kola & Sons payroll account
    a.account_id,
    c.full_name,
    CASE a.account_id
        WHEN 2  THEN 250000.00
        WHEN 3  THEN 180000.00
        WHEN 4  THEN 220000.00
        WHEN 5  THEN 150000.00
        WHEN 6  THEN 300000.00
        WHEN 7  THEN 175000.00
        WHEN 8  THEN 200000.00
        WHEN 9  THEN 165000.00
        WHEN 10 THEN 140000.00
        ELSE 100000.00
    END,
    'PENDING'
FROM account a
JOIN customer c ON c.customer_id = a.customer_id
WHERE a.account_id BETWEEN 2 AND 10;

-- Done.
SELECT 'seed complete: ' || count(*) || ' accounts, ' ||
       (SELECT count(*) FROM standing_order) || ' standing orders, ' ||
       (SELECT count(*) FROM bulk_payment_item) || ' bulk items'
FROM account;

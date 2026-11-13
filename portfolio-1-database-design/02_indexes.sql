-- 02_indexes.sql
-- Indexes every FK column that triggers or reports use, plus supporting indexes
-- for the Portfolio 2 reports. Idempotent (CREATE INDEX IF NOT EXISTS).

-- FK columns that joins and reports rely on.
CREATE INDEX IF NOT EXISTS idx_account_customer      ON account(customer_id);
CREATE INDEX IF NOT EXISTS idx_account_branch        ON account(branch_id);
CREATE INDEX IF NOT EXISTS idx_account_type          ON account(account_type_id);

CREATE INDEX IF NOT EXISTS idx_transfer_debit        ON transfer(debit_account_id);
CREATE INDEX IF NOT EXISTS idx_transfer_credit       ON transfer(credit_account_id);
CREATE INDEX IF NOT EXISTS idx_transfer_batch        ON transfer(settlement_batch_id);
CREATE INDEX IF NOT EXISTS idx_transfer_status       ON transfer(status);
CREATE INDEX IF NOT EXISTS idx_transfer_created_at   ON transfer(created_at);
CREATE INDEX IF NOT EXISTS idx_transfer_channel      ON transfer(channel);

CREATE INDEX IF NOT EXISTS idx_ledger_transfer       ON ledger_entry(transfer_id);
CREATE INDEX IF NOT EXISTS idx_ledger_account        ON ledger_entry(account_id);
CREATE INDEX IF NOT EXISTS idx_ledger_direction      ON ledger_entry(direction);
CREATE INDEX IF NOT EXISTS idx_ledger_created_at     ON ledger_entry(created_at);

CREATE INDEX IF NOT EXISTS idx_standing_debit        ON standing_order(debit_account_id);
CREATE INDEX IF NOT EXISTS idx_standing_credit       ON standing_order(credit_account_id);
CREATE INDEX IF NOT EXISTS idx_standing_status_run   ON standing_order(status, next_run_date);

CREATE INDEX IF NOT EXISTS idx_bulk_batch            ON bulk_payment_item(settlement_batch_id);
CREATE INDEX IF NOT EXISTS idx_bulk_debit            ON bulk_payment_item(debit_account_id);
CREATE INDEX IF NOT EXISTS idx_bulk_credit           ON bulk_payment_item(credit_account_id);
CREATE INDEX IF NOT EXISTS idx_bulk_status           ON bulk_payment_item(status);

-- Composite index used by the "account statement" report: list ledger entries
-- for one account ordered by date.
CREATE INDEX IF NOT EXISTS idx_ledger_account_date   ON ledger_entry(account_id, created_at);

-- Composite index used by the "branch daily transaction value" aggregate.
CREATE INDEX IF NOT EXISTS idx_transfer_created_debit ON transfer(created_at, debit_account_id);

-- 01_partitioning.sql
-- Monthly RANGE partitioning of ledger_entry (the biggest table) by created_at.
-- A DO loop creates one partition per month for every month present in the data
-- plus next month, then a DEFAULT partition catches any out-of-range row.
-- Unique keys on a partitioned table MUST include the partition key (created_at),
-- so the PRIMARY KEY is (ledger_id, created_at).
-- PG16 does not allow exclusion constraints on a partitioned parent, so none are
-- declared here.
-- The script prints rows per partition and one pruned one-month EXPLAIN ANALYZE.
-- The script is idempotent: it drops the partitioned parent each run.

SET timezone TO 'Africa/Lagos';

-- Drop the partitioned demo table (cascades to all partitions).
DROP TABLE IF EXISTS ledger_entry_part CASCADE;

-- ----------------------------------------------------------------------
-- Partitioned parent. PRIMARY KEY includes the partition key (created_at).
-- No FKs are declared on the partitioned parent (the source-of-truth FKs
-- already live on the original ledger_entry table in portfolio-1).
-- ----------------------------------------------------------------------
CREATE TABLE ledger_entry_part (
    ledger_id   BIGINT       NOT NULL,
    transfer_id BIGINT       NOT NULL,
    account_id  BIGINT       NOT NULL,
    direction   VARCHAR(6)   NOT NULL CHECK (direction IN ('DEBIT','CREDIT')),
    amount      NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    narration   VARCHAR(160),
    PRIMARY KEY (ledger_id, created_at)
) PARTITION BY RANGE (created_at);

-- ----------------------------------------------------------------------
-- DO loop: create one partition per month for every month present in the
-- source ledger_entry data, PLUS next month relative to today. This ensures
-- every existing row lands in a real partition and next month's inserts also
-- have a home before they hit the DEFAULT.
-- ----------------------------------------------------------------------
DO $$
DECLARE
    data_min    DATE;
    data_max    DATE;
    next_month  DATE;
    cur         DATE;
    month_end   DATE;
    part_name   TEXT;
BEGIN
    SELECT DATE_TRUNC('month', MIN(created_at))::DATE,
           DATE_TRUNC('month', MAX(created_at))::DATE
      INTO data_min, data_max
    FROM ledger_entry;

    -- Always cover up to the first day of next month relative to today,
    -- even if the data does not extend that far forward.
    next_month := DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month')::DATE;

    IF data_max < next_month THEN
        data_max := next_month;
    END IF;

    cur := data_min;
    WHILE cur <= data_max LOOP
        month_end := (cur + INTERVAL '1 month')::DATE;
        part_name := 'ledger_entry_part_' || to_char(cur, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF ledger_entry_part FOR VALUES FROM (%L) TO (%L)',
            part_name, cur, month_end
        );
        cur := month_end;
    END LOOP;
END $$;

-- DEFAULT partition catches any row whose created_at falls outside the range.
CREATE TABLE IF NOT EXISTS ledger_entry_part_default PARTITION OF ledger_entry_part DEFAULT;

-- ----------------------------------------------------------------------
-- Copy data from the source ledger_entry into the partitioned parent.
-- Each row routes to the right monthly partition automatically.
-- ----------------------------------------------------------------------
INSERT INTO ledger_entry_part (ledger_id, transfer_id, account_id, direction, amount, created_at, narration)
SELECT ledger_id, transfer_id, account_id, direction, amount, created_at, narration
FROM ledger_entry;

-- ----------------------------------------------------------------------
-- Print rows per partition.
-- ----------------------------------------------------------------------
\echo '=== Rows per partition ==='
SELECT
    tableoid::regclass::text AS partition_name,
    count(*) AS row_count
FROM ledger_entry_part
GROUP BY tableoid::regclass::text
ORDER BY partition_name;

-- ----------------------------------------------------------------------
-- Print one pruned one-month EXPLAIN ANALYZE.
-- The query asks for a single month; the planner should scan only that
-- partition (Subplan Removed / Scan only the matching partition).
-- ----------------------------------------------------------------------
\echo '=== EXPLAIN ANALYZE: single-month pruning ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM ledger_entry_part
WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)
  AND created_at <  DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month');

-- Also show the previous-month scan for comparison (will scan a different partition).
\echo '=== EXPLAIN ANALYZE: previous-month pruning ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM ledger_entry_part
WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
  AND created_at <  DATE_TRUNC('month', CURRENT_DATE);

\echo '=== 01_partitioning.sql complete ==='

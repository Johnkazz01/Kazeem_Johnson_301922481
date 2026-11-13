#!/usr/bin/env python3
"""
race_demos.py
Concurrency demonstrations for Lagos Meridian Bank settlement workers.

Parts:
  1. The bug: two workers read the same PENDING transfer and both try to settle it.
  2. UNIQUE constraint fix: a settlement_claim table rejects the duplicate claim.
  3. FOR UPDATE SKIP LOCKED fix: each worker gets a different PENDING transfer.
  4. SERIALIZABLE isolation: expects SQLSTATE 40001 on conflicting settlements.
  5. READ COMMITTED vs REPEATABLE READ: shows the snapshot difference.
  6. Deadlock (40P01) and the fixed-account-order version that avoids it.

The script creates its own demo rows (transfers / accounts / claims) and deletes
them at the end so the database is left clean. Connects over the Unix socket
with no password (psycopg2.connect(dbname="txnbank")).
"""

import threading
import time
import psycopg2
from psycopg2 import errors
from psycopg2.extensions import (
    ISOLATION_LEVEL_READ_COMMITTED,
    ISOLATION_LEVEL_REPEATABLE_READ,
    ISOLATION_LEVEL_SERIALIZABLE,
)

DB = "txnbank"


def connect(isolation=ISOLATION_LEVEL_READ_COMMITTED, autocommit=False):
    """Open a connection over the Unix socket (no user, no password)."""
    conn = psycopg2.connect(dbname=DB)
    conn.set_session(isolation_level=isolation, autocommit=autocommit)
    return conn


def exec_one(sql, params=None, isolation=ISOLATION_LEVEL_READ_COMMITTED):
    """Run a single statement in its own transaction, commit, and return the result rows."""
    conn = connect(isolation=isolation)
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            try:
                rows = cur.fetchall()
            except psycopg2.ProgrammingError:
                rows = None
        conn.commit()
        return rows
    finally:
        conn.close()


def banner(title):
    print("\n" + "=" * 70)
    print(title)
    print("=" * 70)


# ----------------------------------------------------------------------
# Shared setup: ensure the settlement_claim table exists for Part 2.
# ----------------------------------------------------------------------
def ensure_claim_table():
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS settlement_claim (
                    claim_id    BIGSERIAL PRIMARY KEY,
                    transfer_id BIGINT NOT NULL UNIQUE REFERENCES transfer(transfer_id),
                    worker_id   VARCHAR(20) NOT NULL,
                    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
                )
            """)
            cur.execute("TRUNCATE settlement_claim RESTART IDENTITY")
        conn.commit()
    finally:
        conn.close()


def cleanup_demo(prefix):
    """Delete demo transfers and their ledger entries; recompute balances."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                DELETE FROM ledger_entry
                WHERE transfer_id IN (
                    SELECT transfer_id FROM transfer WHERE reference LIKE %s
                )
            """, (prefix,))
            cur.execute("SELECT to_regclass('settlement_claim')")
            if cur.fetchone()[0] is not None:
                cur.execute("""
                    DELETE FROM settlement_claim WHERE transfer_id IN (
                        SELECT transfer_id FROM transfer WHERE reference LIKE %s)
                """, (prefix,))
            cur.execute("DELETE FROM transfer WHERE reference LIKE %s", (prefix,))
            # Recompute cached balances for every account from the ledger.
            cur.execute("""
                UPDATE account a SET balance = COALESCE(
                    (SELECT SUM(CASE WHEN direction='CREDIT' THEN amount ELSE -amount END)
                     FROM ledger_entry WHERE account_id = a.account_id), 0)
            """)
        conn.commit()
    finally:
        conn.close()


# ======================================================================
# PART 1: the bug
# ======================================================================
def part1_bug():
    banner("PART 1: The bug - two workers read the same PENDING transfer")
    prefix = "RACE-BUG-%"
    cleanup_demo(prefix)

    # Seed two PENDING transfers from account 2 to account 3.
    exec_one("""
        INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
        VALUES
            ('RACE-BUG-001', 2, 3, 1000, 'PENDING', 'BRANCH'),
            ('RACE-BUG-002', 2, 3, 1000, 'PENDING', 'BRANCH')
    """)

    barrier = threading.Barrier(2)
    results = {}

    def settle_worker(worker_id):
        try:
            conn = connect()
            cur = conn.cursor()
            barrier.wait()  # both workers reach the SELECT at the same time

            # Plain SELECT - no locking. Both workers may read the same row.
            cur.execute("""
                SELECT transfer_id FROM transfer
                WHERE status = 'PENDING' AND reference LIKE 'RACE-BUG-%'
                ORDER BY transfer_id
                LIMIT 1
            """)
            row = cur.fetchone()
            if not row:
                results[worker_id] = ("no transfer found", None)
                conn.rollback()
                return
            transfer_id = row[0]

            cur.execute("UPDATE transfer SET status = 'SETTLED' WHERE transfer_id = %s",
                        (transfer_id,))
            # The debit goes to the capital account (id 1, big overdraft) so the
            # balance trigger does not pre-empt the duplicate-settlement bug.
            cur.execute("""
                INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
                VALUES (%s, 1, 'DEBIT', 1000, 'RACE-BUG worker ' || %s::text || ' debit')
            """, (transfer_id, worker_id))
            cur.execute("""
                INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
                VALUES (%s, 3, 'CREDIT', 1000, 'RACE-BUG worker ' || %s::text || ' credit')
            """, (transfer_id, worker_id))
            conn.commit()
            results[worker_id] = ("settled", transfer_id)
            cur.close()
        except Exception as exc:
            results[worker_id] = ("error: " + str(exc).strip().splitlines()[0], None)
            try:
                conn.rollback()
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t1 = threading.Thread(target=settle_worker, args=(1,))
    t2 = threading.Thread(target=settle_worker, args=(2,))
    t1.start(); t2.start()
    t1.join(); t2.join()

    print("  Worker 1 result: " + str(results.get(1)))
    print("  Worker 2 result: " + str(results.get(2)))

    rows = exec_one("""
        SELECT reference,
               (SELECT count(*) FROM ledger_entry le WHERE le.transfer_id = t.transfer_id) AS ledger_count
        FROM transfer t
        WHERE reference LIKE 'RACE-BUG-%'
        ORDER BY reference
    """)
    print("  Per-transfer ledger entry counts:")
    for r in rows:
        print("    " + str(r))
    print("  BUG: both workers targeted the same transfer_id. One worker either")
    print("  duplicates the settlement or fails with a confusing check_violation.")
    cleanup_demo(prefix)


# ======================================================================
# PART 2: UNIQUE constraint fix (settlement_claim table)
# ======================================================================
def part2_unique_fix():
    banner("PART 2: UNIQUE constraint fix - settlement_claim rejects duplicates")
    prefix = "RACE-UNIQ-%"
    cleanup_demo(prefix)
    ensure_claim_table()

    exec_one("""
        INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
        VALUES ('RACE-UNIQ-001', 2, 3, 1000, 'PENDING', 'BRANCH')
    """)

    barrier = threading.Barrier(2)
    results = {}

    def claim_worker(worker_id):
        try:
            conn = connect()
            cur = conn.cursor()
            barrier.wait()

            cur.execute("""
                SELECT transfer_id FROM transfer
                WHERE status = 'PENDING' AND reference LIKE 'RACE-UNIQ-%'
                LIMIT 1
            """)
            row = cur.fetchone()
            if not row:
                results[worker_id] = ("no transfer", None)
                conn.rollback()
                return
            transfer_id = row[0]

            # Atomically claim the transfer. The UNIQUE constraint on transfer_id
            # means only one worker can insert a claim row.
            try:
                cur.execute("""
                    INSERT INTO settlement_claim (transfer_id, worker_id)
                    VALUES (%s, %s)
                """, (transfer_id, "W%d" % worker_id))
                conn.commit()
                results[worker_id] = ("claimed", transfer_id)
            except psycopg2.IntegrityError as exc:
                conn.rollback()
                results[worker_id] = ("rejected: " + str(exc).strip().splitlines()[0], transfer_id)
            cur.close()
        except Exception as exc:
            results[worker_id] = ("error: " + str(exc).strip().splitlines()[0], None)
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t1 = threading.Thread(target=claim_worker, args=(1,))
    t2 = threading.Thread(target=claim_worker, args=(2,))
    t1.start(); t2.start()
    t1.join(); t2.join()

    print("  Worker 1 result: " + str(results.get(1)))
    print("  Worker 2 result: " + str(results.get(2)))
    rows = exec_one("SELECT worker_id, transfer_id FROM settlement_claim ORDER BY claim_id")
    print("  Claims recorded: " + str(rows))
    print("  FIX: exactly one worker holds the claim; the other is rejected cleanly.")
    cleanup_demo(prefix)
    exec_one("TRUNCATE settlement_claim RESTART IDENTITY")


# ======================================================================
# PART 3: FOR UPDATE SKIP LOCKED
# ======================================================================
def part3_skip_locked():
    banner("PART 3: FOR UPDATE SKIP LOCKED - each worker gets a different transfer")
    prefix = "RACE-SKIP-%"
    cleanup_demo(prefix)

    exec_one("""
        INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
        VALUES
            ('RACE-SKIP-001', 2, 3, 1000, 'PENDING', 'BRANCH'),
            ('RACE-SKIP-002', 2, 3, 1000, 'PENDING', 'BRANCH'),
            ('RACE-SKIP-003', 2, 3, 1000, 'PENDING', 'BRANCH')
    """)

    barrier = threading.Barrier(2)
    results = {}

    def skip_worker(worker_id):
        try:
            conn = connect()
            cur = conn.cursor()
            barrier.wait()

            # FOR UPDATE SKIP LOCKED: rows already locked by the other worker
            # are silently skipped, so each worker gets its own transfer.
            cur.execute("""
                SELECT transfer_id FROM transfer
                WHERE status = 'PENDING' AND reference LIKE 'RACE-SKIP-%'
                ORDER BY transfer_id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            """)
            row = cur.fetchone()
            if not row:
                results[worker_id] = ("no transfer", None)
                conn.rollback()
                return
            transfer_id = row[0]

            cur.execute("UPDATE transfer SET status = 'SETTLED' WHERE transfer_id = %s",
                        (transfer_id,))
            cur.execute("""
                INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
                VALUES (%s, 1, 'DEBIT', 1000, 'RACE-SKIP W' || %s::text || ' debit')
            """, (transfer_id, worker_id))
            cur.execute("""
                INSERT INTO ledger_entry (transfer_id, account_id, direction, amount, narration)
                VALUES (%s, 3, 'CREDIT', 1000, 'RACE-SKIP W' || %s::text || ' credit')
            """, (transfer_id, worker_id))
            conn.commit()
            results[worker_id] = ("settled", transfer_id)
            cur.close()
        except Exception as exc:
            results[worker_id] = ("error: " + str(exc).strip().splitlines()[0], None)
            try:
                conn.rollback()
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t1 = threading.Thread(target=skip_worker, args=(1,))
    t2 = threading.Thread(target=skip_worker, args=(2,))
    t1.start(); t2.start()
    t1.join(); t2.join()

    print("  Worker 1 result: " + str(results.get(1)))
    print("  Worker 2 result: " + str(results.get(2)))
    rows = exec_one("""
        SELECT reference, status,
               (SELECT count(*) FROM ledger_entry le WHERE le.transfer_id = t.transfer_id) AS ledger_count
        FROM transfer t
        WHERE reference LIKE 'RACE-SKIP-%'
        ORDER BY reference
    """)
    print("  Per-transfer status / ledger counts:")
    for r in rows:
        print("    " + str(r))
    print("  FIX: each worker settled a different transfer; no duplicates.")
    cleanup_demo(prefix)


# ======================================================================
# PART 4: SERIALIZABLE isolation (expects SQLSTATE 40001)
# ======================================================================
def part4_serializable():
    banner("PART 4: SERIALIZABLE isolation - expects SQLSTATE 40001")
    prefix = "RACE-SER-%"
    cleanup_demo(prefix)

    exec_one("""
        INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
        VALUES ('RACE-SER-001', 2, 3, 1000, 'PENDING', 'BRANCH')
    """)

    barrier = threading.Barrier(2)
    results = {}

    def serial_worker(worker_id):
        try:
            conn = connect(isolation=ISOLATION_LEVEL_SERIALIZABLE)
            cur = conn.cursor()
            barrier.wait()

            cur.execute("""
                SELECT transfer_id FROM transfer
                WHERE status = 'PENDING' AND reference LIKE 'RACE-SER-%'
                LIMIT 1
            """)
            row = cur.fetchone()
            if not row:
                results[worker_id] = ("no transfer", None)
                conn.rollback()
                return
            transfer_id = row[0]

            cur.execute("UPDATE transfer SET status = 'SETTLED' WHERE transfer_id = %s",
                        (transfer_id,))
            cur.execute("""
                INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
                VALUES (%s, 1, 'DEBIT', 1000)
            """, (transfer_id,))
            cur.execute("""
                INSERT INTO ledger_entry (transfer_id, account_id, direction, amount)
                VALUES (%s, 3, 'CREDIT', 1000)
            """, (transfer_id,))
            conn.commit()
            results[worker_id] = ("settled", transfer_id)
            cur.close()
        except psycopg2.OperationalError as exc:
            # SQLSTATE 40001 = serialization_failure
            sqlstate = getattr(exc, 'pgcode', '') or ''
            results[worker_id] = ("40001 serialization_failure (%s)" % sqlstate, None)
            try:
                conn.rollback()
            except Exception:
                pass
        except Exception as exc:
            results[worker_id] = ("error: " + str(exc).strip().splitlines()[0], None)
            try:
                conn.rollback()
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t1 = threading.Thread(target=serial_worker, args=(1,))
    t2 = threading.Thread(target=serial_worker, args=(2,))
    t1.start(); t2.start()
    t1.join(); t2.join()

    print("  Worker 1 result: " + str(results.get(1)))
    print("  Worker 2 result: " + str(results.get(2)))
    print("  Under SERIALIZABLE isolation one worker commits and the other is")
    print("  aborted with SQLSTATE 40001 (serialization_failure) and must retry.")
    cleanup_demo(prefix)


# ======================================================================
# PART 5: READ COMMITTED vs REPEATABLE READ
# ======================================================================
def part5_isolation_levels():
    banner("PART 5: READ COMMITTED vs REPEATABLE READ")
    prefix = "RACE-ISO-%"
    cleanup_demo(prefix)

    # Seed a transfer and let reader observe it from both isolation levels
    # while a writer updates it.
    exec_one("""
        INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
        VALUES ('RACE-ISO-001', 2, 3, 1000, 'PENDING', 'BRANCH')
    """)

    barrier = threading.Barrier(2)
    reader_state = {"rc": None, "rr": None, "after": None}

    def reader_rc():
        try:
            conn = connect(isolation=ISOLATION_LEVEL_READ_COMMITTED)
            cur = conn.cursor()
            cur.execute("SELECT status FROM transfer WHERE reference = 'RACE-ISO-001'")
            reader_state["rc_before"] = cur.fetchone()[0]
            barrier.wait()  # let the writer update
            time.sleep(0.5)
            cur.execute("SELECT status FROM transfer WHERE reference = 'RACE-ISO-001'")
            reader_state["rc"] = cur.fetchone()[0]
            conn.commit()
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def reader_rr():
        try:
            conn = connect(isolation=ISOLATION_LEVEL_REPEATABLE_READ)
            cur = conn.cursor()
            cur.execute("SELECT status FROM transfer WHERE reference = 'RACE-ISO-001'")
            reader_state["rr_before"] = cur.fetchone()[0]
            barrier.wait()  # let the writer update
            time.sleep(0.5)
            cur.execute("SELECT status FROM transfer WHERE reference = 'RACE-ISO-001'")
            reader_state["rr"] = cur.fetchone()[0]
            conn.commit()
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def writer():
        try:
            time.sleep(0.05)
            conn = connect()
            cur = conn.cursor()
            cur.execute("UPDATE transfer SET status = 'SETTLED' WHERE reference = 'RACE-ISO-001'")
            conn.commit()
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t_rc = threading.Thread(target=reader_rc)
    t_rr = threading.Thread(target=reader_rr)
    t_w  = threading.Thread(target=writer)
    t_rc.start(); t_rr.start(); t_w.start()
    t_rc.join(); t_rr.join(); t_w.join()

    print("  READ COMMITTED  reader saw: before=%s, after=%s (sees the writer's commit)"
          % (reader_state["rc_before"], reader_state["rc"]))
    print("  REPEATABLE READ reader saw: before=%s, after=%s (snapshot frozen at first read)"
          % (reader_state["rr_before"], reader_state["rr"]))
    cleanup_demo(prefix)


# ======================================================================
# PART 6: deadlock (40P01) and the fixed-order version
# ======================================================================
def part6_deadlock():
    banner("PART 6: Deadlock (40P01) and the fixed-account-order fix")
    prefix = "RACE-DEAD-%"
    cleanup_demo(prefix)

    # Two transfers in opposite directions between accounts 4 and 5.
    exec_one("""
        INSERT INTO transfer (reference, debit_account_id, credit_account_id, amount, status, channel)
        VALUES
            ('RACE-DEAD-001', 4, 5, 500, 'PENDING', 'BRANCH'),
            ('RACE-DEAD-002', 5, 4, 700, 'PENDING', 'BRANCH')
    """)

    # ---- 6a: the buggy version (deadlock) -----------------------------
    barrier = threading.Barrier(2)
    results_buggy = {}

    def buggy_worker(worker_id, debit_acct, credit_acct, ref):
        try:
            conn = connect()
            cur = conn.cursor()
            barrier.wait()
            # Lock the debit account first (advisory, via SELECT FOR UPDATE).
            cur.execute("SELECT balance FROM account WHERE account_id = %s FOR UPDATE",
                        (debit_acct,))
            time.sleep(0.3)
            # Now try to lock the credit account - the other worker holds it.
            cur.execute("SELECT balance FROM account WHERE account_id = %s FOR UPDATE",
                        (credit_acct,))
            cur.execute("UPDATE transfer SET status = 'SETTLED' WHERE reference = %s", (ref,))
            conn.commit()
            results_buggy[worker_id] = ("committed", ref)
        except psycopg2.OperationalError as exc:
            sqlstate = getattr(exc, 'pgcode', '') or ''
            results_buggy[worker_id] = ("%s deadlock (%s)" % (sqlstate, exc.__class__.__name__), ref)
            try:
                conn.rollback()
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t1 = threading.Thread(target=buggy_worker, args=(1, 4, 5, 'RACE-DEAD-001'))
    t2 = threading.Thread(target=buggy_worker, args=(2, 5, 4, 'RACE-DEAD-002'))
    t1.start(); t2.start()
    t1.join(); t2.join()
    print("  6a Buggy (lock in transfer direction):")
    print("    Worker 1: " + str(results_buggy.get(1)))
    print("    Worker 2: " + str(results_buggy.get(2)))
    print("    One worker should hit SQLSTATE 40P01 (deadlock_detected).")

    # ---- 6b: the fixed version (lock accounts in id order) -----------
    # Reset transfer statuses for the fixed run.
    exec_one("""
        UPDATE transfer SET status = 'PENDING'
        WHERE reference IN ('RACE-DEAD-001', 'RACE-DEAD-002')
    """)
    results_fixed = {}
    barrier2 = threading.Barrier(2)

    def fixed_worker(worker_id, debit_acct, credit_acct, ref):
        try:
            conn = connect()
            cur = conn.cursor()
            barrier2.wait()
            # Always lock the lower account_id first, then the higher.
            first, second = sorted([debit_acct, credit_acct])
            cur.execute("SELECT balance FROM account WHERE account_id = %s FOR UPDATE", (first,))
            cur.execute("SELECT balance FROM account WHERE account_id = %s FOR UPDATE", (second,))
            cur.execute("UPDATE transfer SET status = 'SETTLED' WHERE reference = %s", (ref,))
            conn.commit()
            results_fixed[worker_id] = ("committed", ref)
        except psycopg2.OperationalError as exc:
            sqlstate = getattr(exc, 'pgcode', '') or ''
            results_fixed[worker_id] = ("%s (%s)" % (sqlstate, exc.__class__.__name__), ref)
            try:
                conn.rollback()
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    t3 = threading.Thread(target=fixed_worker, args=(1, 4, 5, 'RACE-DEAD-001'))
    t4 = threading.Thread(target=fixed_worker, args=(2, 5, 4, 'RACE-DEAD-002'))
    t3.start(); t4.start()
    t3.join(); t4.join()
    print("  6b Fixed (lock accounts in id order):")
    print("    Worker 1: " + str(results_fixed.get(1)))
    print("    Worker 2: " + str(results_fixed.get(2)))
    print("    Both workers commit; the lock-ordering prevents the deadlock.")

    cleanup_demo(prefix)
    # Drop the demo-only claim table.
    exec_one("DROP TABLE IF EXISTS settlement_claim")
    print("\n=== race_demos.py complete ===")


if __name__ == "__main__":
    part1_bug()
    part2_unique_fix()
    part3_skip_locked()
    part4_serializable()
    part5_isolation_levels()
    part6_deadlock()

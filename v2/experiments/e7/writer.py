"""Drill writer (E7, chapter 8): numbered INSERTs into drill.writes at a fixed rate, every attempt
logged with its outcome, so that a failover can be measured from the client's side.

  conn <t> <server address> <in recovery>    a new connection, and where it landed
  ok   <seq> <t> <ms>                        the commit was acknowledged
  fail <seq> <t> <ms> <reason>               definitely not written: no connection, or the server
                                             answered with an error (e.g. read-only after a demotion)
  unk  <seq> <t> <ms> <reason>               the INSERT was sent, no answer within DEADLINE s:
                                             committed or not - unknown to the client

A lost write is an "ok" whose row is missing afterwards (writer_report.py). No statement_timeout
and no query cancel: cancelling a commit that waits for a synchronous standby returns *success*
with only a WARNING ("might not have been replicated"). On a deadline the connection is dropped.
psycopg2 runs in asynchronous mode so that every wait has a deadline: a frozen server's kernel
still acknowledges TCP, so keepalives alone would never end the wait.
"""
import os
import select
import sys
import time

import psycopg2
import psycopg2.extensions as ext

RUN = os.environ["RUN"]
RATE = float(os.environ.get("RATE", "50"))
DEADLINE = float(os.environ.get("DEADLINE", "2"))
DSN = os.environ.get(
    "DSN",
    "host=pg-main-rw.data.svc port=5432 dbname=drill user=drill application_name=drill-writer",
)  # password: PGPASSWORD


def out(*fields):
    print(*fields, flush=True)


def wait(conn, until):
    while True:
        state = conn.poll()
        if state == ext.POLL_OK:
            return
        left = until - time.monotonic()
        if left <= 0:
            raise TimeoutError("deadline")
        if state == ext.POLL_READ:
            select.select([conn.fileno()], [], [], left)
        elif state == ext.POLL_WRITE:
            select.select([], [conn.fileno()], [], left)


def run(conn, sql, args=None, until=None):
    cur = conn.cursor()
    cur.execute(sql, args)
    wait(conn, until or time.monotonic() + DEADLINE)
    return cur


def connect():
    conn = psycopg2.connect(DSN, async_=1)
    wait(conn, time.monotonic() + DEADLINE)
    row = run(conn, "SELECT inet_server_addr()::text, pg_is_in_recovery()").fetchone()
    out("conn", f"{time.time():.3f}", row[0], row[1])
    return conn


def main():
    conn = connect()
    run(conn, "CREATE TABLE IF NOT EXISTS writes (run text, seq bigint, client_ts timestamptz,"
              " server_ts timestamptz DEFAULT clock_timestamp(), PRIMARY KEY (run, seq))")
    out("start", RUN, f"rate={RATE}", f"deadline={DEADLINE}")
    interval, seq, nxt = 1 / RATE, 0, time.monotonic()
    while True:
        seq += 1
        t0, m0 = time.time(), time.monotonic()
        sent = False
        try:
            if conn is None:
                conn = connect()
            sent = True
            run(conn, "INSERT INTO writes (run, seq, client_ts) VALUES (%s, %s, to_timestamp(%s))",
                (RUN, seq, t0))
            out("ok", seq, f"{t0:.3f}", f"{(time.monotonic() - m0) * 1000:.1f}")
        except psycopg2.Error as e:
            # an answer from the server (pgcode set) means the INSERT did not commit
            known = (not sent) or e.pgcode is not None
            reason = e.pgcode or type(e).__name__
            out("fail" if known else "unk", seq, f"{t0:.3f}", f"{(time.monotonic() - m0) * 1000:.1f}", reason)
            conn = drop(conn)
        except (TimeoutError, OSError) as e:
            out("unk" if sent else "fail", seq, f"{t0:.3f}", f"{(time.monotonic() - m0) * 1000:.1f}",
                type(e).__name__)
            conn = drop(conn)
        nxt += interval
        pause = nxt - time.monotonic()
        if pause > 0:
            time.sleep(pause)
        else:
            nxt = time.monotonic()


def drop(conn):
    try:
        if conn is not None:
            conn.close()  # closes the socket; no cancel request is sent
    except Exception:  # noqa: BLE001
        pass
    time.sleep(0.1)
    return None


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)

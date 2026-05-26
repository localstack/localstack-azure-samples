import os


def worker_int(worker):
    # SIGINT (Ctrl+C) default path raises SystemExit inside the worker's recv()
    # loop, dumping a traceback through gunicorn's HTTP parser frames. os._exit
    # short-circuits the unwind for a clean foreground stop. SIGTERM (graceful)
    # is unaffected — it goes through a different code path.
    os._exit(0)


def worker_abort(worker):
    # SIGABRT is what the arbiter sends when a worker misses its heartbeat
    # ([CRITICAL] WORKER TIMEOUT). The default handler does sys.exit(1), which
    # unwinds through the same recv() stack as SIGINT and prints a misleading
    # traceback. The WORKER TIMEOUT log line above it is the real diagnostic;
    # exit at the C level to suppress the spurious trace.
    os._exit(1)

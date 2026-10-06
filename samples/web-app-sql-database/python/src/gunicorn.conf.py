import os
import threading


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


def when_ready(server):
    # App Service starts the app with gunicorn, so the `if __name__ == '__main__'` branch of app.py, which serves
    # HTTPS on port 8443 with the Key Vault certificate, never runs there. Start that listener here, once, in the
    # gunicorn master, next to the HTTP port App Service proxies to.
    vault_uri = os.environ.get("KEYVAULT_URI")
    cert_name = os.environ.get("CERT_NAME")
    if not (vault_uri and cert_name):
        return
    try:
        from werkzeug.serving import make_server

        from app import app
        from certificates import get_ssl_context_from_keyvault

        https_server = make_server(
            "0.0.0.0", 8443, app, threaded=True, ssl_context=get_ssl_context_from_keyvault(vault_uri, cert_name)
        )
    except Exception:
        server.log.exception("HTTPS on port 8443 is disabled: certificate [%s] could not be loaded", cert_name)
        return
    threading.Thread(target=https_server.serve_forever, name="https-8443", daemon=True).start()
    server.log.info("HTTPS enabled on port 8443 with Key Vault certificate [%s]", cert_name)

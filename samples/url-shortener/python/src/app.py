import datetime
import hashlib
import hmac
import json
import logging
import os
import secrets
import string

import psycopg2
import qrcode
import qrcode.image.svg
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.data.tables import TableServiceClient, UpdateMode
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.storage.queue import QueueClient, TextBase64EncodePolicy
from flask import Flask, abort, jsonify, redirect, render_template_string, request
from io import BytesIO

app = Flask(__name__)
LOG = logging.getLogger(__name__)

TABLE_NAME = os.environ.get("LINKS_TABLE", "links")
PARTITION = "links"
CODE_ALPHABET = string.ascii_letters + string.digits
CODE_LENGTH = 6

_credential = None
_table = None
_sign_key = None
_pg_conn_str = None
_sb_client = None
_queue = None


def credential():
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


def table():
    global _table
    if _table is None:
        # STORAGE_CONN switches the storage data planes to connection-string auth
        # (used on real Azure when the deploying principal cannot create the
        # managed identity's role assignments); default is credential-free MI.
        conn = os.environ.get("STORAGE_CONN")
        if conn:
            service = TableServiceClient.from_connection_string(conn)
        else:
            service = TableServiceClient(
                endpoint=os.environ["AZURE_TABLES_ENDPOINT"], credential=credential()
            )
        _table = service.create_table_if_not_exists(TABLE_NAME)
    return _table


def secret_client():
    return SecretClient(vault_url=os.environ["KEYVAULT_URL"], credential=credential())


def sign_key():
    global _sign_key
    if _sign_key is None:
        _sign_key = secret_client().get_secret("link-sign-key").value
    return _sign_key


def sign(code):
    return hmac.new(sign_key().encode(), code.encode(), hashlib.sha256).hexdigest()[:8]


def pg():
    """New connection per call; click volume here does not justify pooling."""
    global _pg_conn_str
    if _pg_conn_str is None:
        secret_name = os.environ.get("PG_SECRET_NAME", "pg-conn")
        _pg_conn_str = secret_client().get_secret(secret_name).value
    conn = psycopg2.connect(_pg_conn_str)
    with conn.cursor() as cur:
        cur.execute(
            "CREATE TABLE IF NOT EXISTS clicks ("
            "id serial PRIMARY KEY, code text NOT NULL, ts timestamptz DEFAULT now())"
        )
    conn.commit()
    return conn


def sb_sender():
    global _sb_client
    if _sb_client is None:
        conn = os.environ.get("SB_CONN")
        if conn:
            _sb_client = ServiceBusClient.from_connection_string(conn)
        else:
            _sb_client = ServiceBusClient(
                fully_qualified_namespace=os.environ["SB_FQNS"], credential=credential()
            )
    return _sb_client.get_queue_sender(os.environ["SB_QUEUE"])


def qr_queue():
    global _queue
    if _queue is None:
        conn = os.environ.get("STORAGE_CONN")
        if conn:
            _queue = QueueClient.from_connection_string(
                conn,
                queue_name=os.environ.get("QR_JOBS_QUEUE", "qrjobs"),
                message_encode_policy=TextBase64EncodePolicy(),
            )
        else:
            _queue = QueueClient(
                account_url=os.environ["QUEUE_ENDPOINT"],
                queue_name=os.environ.get("QR_JOBS_QUEUE", "qrjobs"),
                credential=credential(),
                message_encode_policy=TextBase64EncodePolicy(),
            )
    return _queue


def qr_url(code):
    return f"{os.environ['BLOB_ENDPOINT'].rstrip('/')}/{os.environ.get('QR_CONTAINER', 'qrcodes')}/{code}.svg"


PAGE = """<!doctype html>
<html><head><title>linklet cloud</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:860px;margin:3rem auto;padding:0 1rem}
 h1{font-weight:600} form{display:flex;gap:.5rem;margin:1.5rem 0}
 input[type=url]{flex:1;padding:.5rem;border:1px solid #ccc;border-radius:6px}
 button{padding:.5rem 1rem;border:0;border-radius:6px;background:#2563eb;color:#fff;cursor:pointer}
 table{width:100%;border-collapse:collapse} td,th{text-align:left;padding:.4rem;border-bottom:1px solid #eee}
 code{background:#f3f4f6;padding:.1rem .3rem;border-radius:4px}
 .clean{color:#16a34a}.flagged{color:#dc2626}.pending{color:#a16207}
</style></head>
<body>
<h1>linklet cloud</h1>
<p>URL shortener on LocalStack for Azure: App Service, Functions, Table/Queue/Blob Storage,
Key Vault, Service Bus, PostgreSQL, Managed Identity.</p>
<form method="post" action="/shorten">
  <input type="url" name="url" placeholder="https://example.com/very/long/path" required>
  <button type="submit">Shorten</button>
</form>
<table>
<tr><th>Short</th><th>Target</th><th>Hits</th><th>Sig</th><th>Scan</th><th>QR</th></tr>
{% for l in links %}
<tr><td><a href="/l/{{l.code}}"><code>{{l.code}}</code></a></td>
    <td>{{l.url}}</td><td>{{l.hits}}</td><td><code>{{l.sig}}</code></td>
    <td class="{{l.scan}}">{{l.scan}}</td>
    <td>{% if l.qr == 'done' %}<a href="{{l.qr_url}}">svg</a>{% else %}{{l.qr}}{% endif %}</td></tr>
{% endfor %}
</table>
</body></html>"""


def new_code():
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def entity_to_dict(e):
    return {
        "code": e["RowKey"],
        "url": e["url"],
        "hits": e.get("hits", 0),
        "sig": e.get("sig", ""),
        "scan": e.get("scan", "pending"),
        "qr": e.get("qr", "pending"),
        "qr_url": qr_url(e["RowKey"]),
    }


@app.get("/")
def index():
    entities = table().query_entities(f"PartitionKey eq '{PARTITION}'")
    links = sorted((entity_to_dict(e) for e in entities), key=lambda l: -l["hits"])
    return render_template_string(PAGE, links=links)


@app.post("/shorten")
def shorten():
    payload = request.get_json(silent=True) or request.form
    url = (payload.get("url") or "").strip()
    if not url.startswith(("http://", "https://")):
        return jsonify(error="url must start with http:// or https://"), 400
    for _ in range(3):
        code = new_code()
        entity = {
            "PartitionKey": PARTITION,
            "RowKey": code,
            "url": url,
            "hits": 0,
            "sig": sign(code),
            "scan": "pending",
            "qr": "pending",
            "created": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
        try:
            table().create_entity(entity)
            break
        except ResourceExistsError:
            continue
    else:
        return jsonify(error="could not allocate a unique code"), 500

    # Fan out to the workers: abuse scan via Service Bus, QR render via Storage Queue.
    with sb_sender() as sender:
        sender.send_messages(ServiceBusMessage(json.dumps({"code": code, "url": url})))
    qr_queue().send_message(json.dumps({"code": code}))

    short_url = request.host_url.rstrip("/") + "/l/" + code
    if request.is_json:
        return jsonify(code=code, short_url=short_url, url=url, sig=entity["sig"]), 201
    return redirect("/")


@app.get("/l/<code>")
def follow(code):
    try:
        entity = table().get_entity(PARTITION, code)
    except ResourceNotFoundError:
        return jsonify(error=f"unknown code {code!r}"), 404
    entity["hits"] = int(entity.get("hits", 0)) + 1
    table().update_entity(entity, mode=UpdateMode.MERGE)
    try:
        conn = pg()
        with conn.cursor() as cur:
            cur.execute("INSERT INTO clicks (code) VALUES (%s)", (code,))
        conn.commit()
        conn.close()
    except Exception as e:
        # Analytics must not break redirects; the click is lost and logged.
        LOG.warning("click logging to postgres failed for %s: %s", code, e)
    return redirect(entity["url"], code=302)


@app.get("/api/links/<code>")
def link_info(code):
    try:
        entity = table().get_entity(PARTITION, code)
    except ResourceNotFoundError:
        return jsonify(error=f"unknown code {code!r}"), 404
    return jsonify(entity_to_dict(entity))


def require_internal_token():
    # Fail closed when INTERNAL_TOKEN is not configured.
    expected = os.environ.get("INTERNAL_TOKEN")
    provided = request.headers.get("X-Internal-Token", "")
    if not expected or not hmac.compare_digest(provided, expected):
        abort(403)


@app.post("/internal/scan-result")
def scan_result():
    require_internal_token()
    body = request.get_json(force=True)
    table().update_entity(
        {"PartitionKey": PARTITION, "RowKey": body["code"], "scan": body["verdict"]},
        mode=UpdateMode.MERGE,
    )
    return jsonify(ok=True)


@app.post("/internal/generate-qr")
def generate_qr():
    require_internal_token()
    body = request.get_json(force=True)
    code = body["code"]
    short_url = request.host_url.rstrip("/") + "/l/" + code
    image = qrcode.make(short_url, image_factory=qrcode.image.svg.SvgPathImage)
    buffer = BytesIO()
    image.save(buffer)
    conn = os.environ.get("STORAGE_CONN")
    if conn:
        blob_service = BlobServiceClient.from_connection_string(conn)
    else:
        blob_service = BlobServiceClient(account_url=os.environ["BLOB_ENDPOINT"], credential=credential())
    blob_client = blob_service.get_blob_client(os.environ.get("QR_CONTAINER", "qrcodes"), f"{code}.svg")
    blob_client.upload_blob(
        buffer.getvalue(),
        overwrite=True,
        content_settings=ContentSettings(content_type="image/svg+xml"),
    )
    table().update_entity(
        {"PartitionKey": PARTITION, "RowKey": code, "qr": "done"},
        mode=UpdateMode.MERGE,
    )
    return jsonify(ok=True)


@app.get("/healthz")
def healthz():
    components = {}
    try:
        table()
        components["table"] = "ok"
    except Exception as e:
        components["table"] = f"error: {e}"
    try:
        sign_key()
        components["keyvault"] = "ok"
    except Exception as e:
        components["keyvault"] = f"error: {e}"
    try:
        conn = pg()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        components["postgres"] = "ok"
    except Exception as e:
        components["postgres"] = f"error: {e}"
    components["servicebus"] = (
        "configured" if (os.environ.get("SB_CONN") or os.environ.get("SB_FQNS")) else "missing config"
    )
    components["qr_queue"] = "configured" if os.environ.get("QUEUE_ENDPOINT") else "missing config"
    ok = all(v in ("ok", "configured") for v in components.values())
    return jsonify(status="ok" if ok else "degraded", components=components), 200 if ok else 503

"""
Notes App — Azure Database for PostgreSQL on LocalStack.

A notes app with full-text search powered by PostgreSQL tsvector,
demonstrating Azure Database for PostgreSQL Flexible Server running on
LocalStack.  Serves as the GUI centerpiece for the unified sample that
also includes Python and C# Azure SDK management demos.
"""

import os
import sys
import time

import psycopg2
from flask import Flask, jsonify, request
from psycopg2.extras import RealDictCursor

PG_USER = os.environ.get("PG_USER", "pgadmin")
PG_PASSWORD = os.environ.get("PG_PASSWORD", "P@ssw0rd12345!")
PG_DATABASE = os.environ.get("PG_DATABASE", "sampledb")
PG_HOST = os.environ.get("PG_HOST", "localhost")
PG_PORT = int(os.environ.get("PG_PORT", "5432"))


def get_conn():
    """Return a fresh psycopg2 connection."""
    return psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        user=PG_USER,
        password=PG_PASSWORD,
        dbname=PG_DATABASE,
    )


def wait_for_pg(max_retries: int = 30, delay: float = 2.0) -> None:
    """Block until PostgreSQL accepts connections."""
    for attempt in range(1, max_retries + 1):
        try:
            conn = get_conn()
            conn.close()
            print(f"PostgreSQL is ready (attempt {attempt})")
            return
        except Exception:
            if attempt == max_retries:
                raise
            print(f"Waiting for PostgreSQL... (attempt {attempt}/{max_retries})")
            time.sleep(delay)


def init_db():
    """Create the notes table if it doesn't exist."""
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id          SERIAL PRIMARY KEY,
                title       VARCHAR(200) NOT NULL,
                content     TEXT NOT NULL,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                search_vector tsvector GENERATED ALWAYS AS (
                    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))
                ) STORED
            )
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_notes_search
            ON notes USING gin(search_vector)
        """)
        conn.commit()
        cur.close()
    finally:
        conn.close()


app = Flask(__name__)

INDEX_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Notes &mdash; Azure DB for PostgreSQL on LocalStack</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f0f2f5;color:#1a1a2e}

/* header */
.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;padding:2rem 1rem;text-align:center}
.header h1{font-size:1.8rem;margin-bottom:.3rem}
.header p{opacity:.85;font-size:.9rem}
.badge{display:inline-block;background:rgba(255,255,255,.2);padding:.15rem .6rem;border-radius:12px;font-size:.75rem;margin-top:.5rem}

/* layout */
.container{max-width:820px;margin:0 auto;padding:1.5rem 1rem}
.card{background:#fff;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,.08);padding:1.25rem 1.5rem;margin-bottom:1rem}

/* search */
.search-bar{margin-bottom:1.25rem}
.search-bar input{width:100%;padding:.7rem 1rem;border:2px solid #e0e0e0;border-radius:8px;font-size:1rem;outline:none;transition:border-color .2s}
.search-bar input:focus{border-color:#667eea}

/* form */
.form-row{display:flex;gap:.5rem;margin-bottom:.75rem}
.form-row input{flex:1;padding:.7rem 1rem;border:2px solid #e0e0e0;border-radius:8px;font-size:1rem;outline:none;transition:border-color .2s}
.form-row input:focus{border-color:#667eea}
textarea{width:100%;padding:.7rem 1rem;border:2px solid #e0e0e0;border-radius:8px;font-size:1rem;font-family:inherit;outline:none;resize:vertical;min-height:72px;margin-bottom:.75rem;transition:border-color .2s}
textarea:focus{border-color:#667eea}

/* buttons */
.btn{padding:.65rem 1.4rem;border:none;border-radius:8px;font-size:.95rem;cursor:pointer;transition:all .15s}
.btn-primary{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff}
.btn-primary:hover{opacity:.9;transform:translateY(-1px)}
.btn-sm{padding:.35rem .7rem;font-size:.8rem;border-radius:6px}
.btn-danger{background:#ff4757;color:#fff}
.btn-danger:hover{background:#e84141}

/* notes */
.note{border-left:4px solid #667eea;transition:box-shadow .15s}
.note:hover{box-shadow:0 4px 14px rgba(0,0,0,.1)}
.note-header{display:flex;justify-content:space-between;align-items:flex-start;gap:.5rem;margin-bottom:.4rem}
.note-title{font-size:1.05rem;font-weight:600;word-break:break-word}
.note-meta{display:flex;gap:.5rem;align-items:center;flex-shrink:0}
.note-time{font-size:.75rem;color:#999;white-space:nowrap}
.note-content{color:#555;line-height:1.55;white-space:pre-wrap;word-break:break-word}

/* stats */
.stats{display:flex;gap:.6rem;margin-bottom:1rem;font-size:.82rem;color:#666;flex-wrap:wrap}
.stats span{background:#e8eaf0;padding:.2rem .7rem;border-radius:20px}

/* empty */
.empty{text-align:center;padding:2.5rem 1rem;color:#aaa}
.empty-icon{font-size:3rem;opacity:.3;margin-bottom:.5rem}

/* sdk panel */
.sdk-panel{margin-bottom:1.5rem}
.sdk-panel h3{font-size:.95rem;margin-bottom:.6rem;color:#444}
.sdk-tabs{display:flex;gap:.3rem;margin-bottom:.8rem}
.sdk-tab{padding:.4rem .9rem;border:2px solid #e0e0e0;border-radius:8px;cursor:pointer;font-size:.85rem;background:#fff;transition:all .15s}
.sdk-tab.active{border-color:#667eea;background:#667eea;color:#fff}
.sdk-log{background:#1a1a2e;color:#a8e6cf;border-radius:8px;padding:1rem;font-family:'JetBrains Mono',Menlo,monospace;font-size:.78rem;line-height:1.6;max-height:320px;overflow-y:auto;white-space:pre-wrap;word-break:break-word}
.sdk-log .pass{color:#a8e6cf}
.sdk-log .fail{color:#ff6b6b}
.sdk-log .info{color:#74b9ff}
.sdk-log .dim{color:#636e72}
.btn-run{background:#27ae60;color:#fff;margin-bottom:.8rem;display:inline-block}
.btn-run:hover{background:#2ecc71;transform:translateY(-1px)}
.btn-run:disabled{background:#95a5a6;cursor:not-allowed;transform:none}

/* powered-by */
.powered{text-align:center;padding:1.5rem;font-size:.8rem;color:#aaa}
.powered a{color:#667eea;text-decoration:none}
</style>
</head>
<body>

<div class="header">
  <h1>Notes</h1>
  <p>Full-text search powered by Azure Database for PostgreSQL</p>
  <span class="badge">Running on LocalStack</span>
</div>

<div class="container">

  <!-- SDK Demo Panel -->
  <div class="card sdk-panel">
    <h3>Azure SDK Management Demos</h3>
    <div class="sdk-tabs">
      <div class="sdk-tab active" onclick="switchTab('python')">Python SDK</div>
      <div class="sdk-tab" onclick="switchTab('dotnet')">C# SDK</div>
    </div>
    <div style="margin-bottom:.8rem">
      <button id="btn-python" class="btn btn-run" onclick="triggerSdk('python')">&#9654; Run Demo</button>
      <button id="btn-dotnet" class="btn btn-run" onclick="triggerSdk('dotnet')" style="display:none">&#9654; Run Demo</button>
    </div>
    <div id="sdk-python" class="sdk-log"><span class="dim">Click &#9654; Run Demo to execute the Python Azure SDK management demo.</span></div>
    <div id="sdk-dotnet" class="sdk-log" style="display:none"><span class="dim">Click &#9654; Run Demo to execute the C# Azure SDK management demo.</span></div>
  </div>

  <!-- Search -->
  <div class="search-bar">
    <input type="text" id="search" placeholder="Search notes (PostgreSQL full-text search)..." oninput="debounceSearch()">
  </div>

  <!-- Create form -->
  <div class="card" style="margin-bottom:1.5rem">
    <div class="form-row">
      <input type="text" id="title" placeholder="Title" onkeydown="if(event.key==='Enter')document.getElementById('content').focus()">
    </div>
    <textarea id="content" placeholder="Write your note..." onkeydown="if(event.ctrlKey&&event.key==='Enter')createNote()"></textarea>
    <button class="btn btn-primary" onclick="createNote()">Add Note</button>
    <span style="margin-left:.5rem;font-size:.75rem;color:#aaa">Ctrl+Enter</span>
  </div>

  <!-- Stats -->
  <div class="stats" id="stats"></div>

  <!-- Notes list -->
  <div id="notes"></div>
</div>

<div class="powered">
  Terraform / Bicep &rarr; Azure DB for PostgreSQL Flexible Server &rarr; Flask &bull;
  Python SDK &bull; C# SDK &bull;
  <a href="https://localstack.cloud" target="_blank">LocalStack</a>
</div>

<script>
let searchTimer,activeTab='python',pollInterval;
let sdkState={python:'idle',dotnet:'idle'};

function debounceSearch(){clearTimeout(searchTimer);searchTimer=setTimeout(doSearch,250)}

async function loadNotes(){renderNotes(await(await fetch('/api/notes')).json())}

async function doSearch(){
  const q=document.getElementById('search').value.trim();
  renderNotes(await(await fetch(q?'/api/notes/search?q='+encodeURIComponent(q):'/api/notes')).json(),q);
}

async function createNote(){
  const t=document.getElementById('title'),c=document.getElementById('content');
  if(!t.value.trim()||!c.value.trim())return;
  await fetch('/api/notes',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title:t.value.trim(),content:c.value.trim()})});
  t.value='';c.value='';t.focus();document.getElementById('search').value='';loadNotes();
}

async function deleteNote(id){
  await fetch('/api/notes/'+id,{method:'DELETE'});
  document.getElementById('search').value.trim()?doSearch():loadNotes();
}

function renderNotes(notes,query){
  const el=document.getElementById('notes'),st=document.getElementById('stats');
  st.innerHTML='<span>'+notes.length+' note'+(notes.length!==1?'s':'')+'</span>'+(query?'<span>Search: &ldquo;'+esc(query)+'&rdquo;</span>':'');
  if(!notes.length){el.innerHTML='<div class="empty"><div class="empty-icon">&#128221;</div><p>'+(query?'No notes match your search.':'No notes yet &mdash; create one above!')+'</p></div>';return}
  el.innerHTML=notes.map(n=>'<div class="card note"><div class="note-header"><span class="note-title">'+esc(n.title)+'</span><div class="note-meta"><span class="note-time">'+fmtDate(n.created_at)+'</span><button class="btn btn-sm btn-danger" onclick="deleteNote('+n.id+')">Delete</button></div></div><div class="note-content">'+esc(n.content)+'</div></div>').join('');
}

function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}
function fmtDate(iso){return new Date(iso).toLocaleString()}

function switchTab(tab){
  activeTab=tab;
  document.querySelectorAll('.sdk-tab').forEach(t=>t.classList.remove('active'));
  document.querySelector('.sdk-tab[onclick*="'+tab+'"]').classList.add('active');
  document.getElementById('sdk-python').style.display=tab==='python'?'block':'none';
  document.getElementById('sdk-dotnet').style.display=tab==='dotnet'?'block':'none';
  document.getElementById('btn-python').style.display=tab==='python'?'inline-block':'none';
  document.getElementById('btn-dotnet').style.display=tab==='dotnet'?'inline-block':'none';
}

async function triggerSdk(lang){
  const btn=document.getElementById('btn-'+lang);
  btn.disabled=true;btn.textContent='Running...';
  sdkState[lang]='running';
  document.getElementById('sdk-'+lang).innerHTML='<span class="dim">Starting '+(lang==='python'?'Python':'C#')+' SDK demo...</span>';
  try{await fetch('/api/sdk-trigger/'+lang,{method:'POST'})}catch(e){}
  clearInterval(pollInterval);pollInterval=setInterval(pollSdkLogs,500);
}

async function pollSdkLogs(){
  for(const lang of ['python','dotnet']){
    try{
      const r=await fetch('/api/sdk-status/'+lang);
      if(!r.ok)continue;
      const data=await r.json();
      const el=document.getElementById('sdk-'+lang);
      if(data.log){el.innerHTML=formatLog(data.log);el.scrollTop=el.scrollHeight}
      if(sdkState[lang]==='running'&&data.status==='done'){
        sdkState[lang]='done';
        const btn=document.getElementById('btn-'+lang);
        btn.disabled=false;btn.innerHTML='&#9654; Run Again';
        if(sdkState.python!=='running'&&sdkState.dotnet!=='running'){
          clearInterval(pollInterval);pollInterval=setInterval(pollSdkLogs,5000);
        }
      }
    }catch(e){}
  }
}

function formatLog(log){
  if(!log)return '<span class="dim">Waiting for SDK demo to start...</span>';
  return log
    .replace(/^(\[\s*\d+\]\s*PASS:.*)/gm,'<span class="pass">$1</span>')
    .replace(/^(\[\s*\d+\]\s*FAIL:.*)/gm,'<span class="fail">$1</span>')
    .replace(/^(={3,}.*)/gm,'<span class="info">$1</span>')
    .replace(/^(TOTAL:.*)/gm,'<span class="info">$1</span>')
    .replace(/^(ALL TESTS PASSED)/gm,'<span class="pass">$1</span>')
    .replace(/^(\d+ TEST.*FAILED)/gm,'<span class="fail">$1</span>');
}

loadNotes();
pollInterval=setInterval(pollSdkLogs,5000);
</script>
</body>
</html>"""


_sdk_status: dict[str, dict] = {
    "python": {"status": "pending", "log": ""},
    "dotnet": {"status": "pending", "log": ""},
}

_sdk_trigger: dict[str, int] = {"python": 0, "dotnet": 0}


@app.route("/")
def index():
    return INDEX_HTML


@app.route("/api/notes", methods=["GET"])
def list_notes():
    conn = get_conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            "SELECT id, title, content, created_at FROM notes ORDER BY created_at DESC"
        )
        notes = cur.fetchall()
        for n in notes:
            n["created_at"] = n["created_at"].isoformat()
        return jsonify(notes)
    finally:
        conn.close()


@app.route("/api/notes", methods=["POST"])
def create_note():
    data = request.get_json(force=True)
    title = (data.get("title") or "").strip()
    content = (data.get("content") or "").strip()
    if not title or not content:
        return jsonify({"error": "Title and content are required"}), 400

    conn = get_conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING id, title, content, created_at",
            (title, content),
        )
        note = cur.fetchone()
        note["created_at"] = note["created_at"].isoformat()
        conn.commit()
        return jsonify(note), 201
    finally:
        conn.close()


@app.route("/api/notes/<int:note_id>", methods=["DELETE"])
def delete_note(note_id):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM notes WHERE id = %s", (note_id,))
        conn.commit()
        return "", 204
    finally:
        conn.close()


@app.route("/api/notes/search")
def search_notes():
    query = (request.args.get("q") or "").strip()
    if not query:
        return list_notes()

    conn = get_conn()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT id, title, content, created_at,
                   ts_rank(search_vector, plainto_tsquery('english', %s)) AS rank
            FROM notes
            WHERE search_vector @@ plainto_tsquery('english', %s)
            ORDER BY rank DESC, created_at DESC
            """,
            (query, query),
        )
        notes = cur.fetchall()
        for n in notes:
            n["created_at"] = n["created_at"].isoformat()
            n.pop("rank", None)
        return jsonify(notes)
    finally:
        conn.close()


@app.route("/api/sdk-status/<lang>", methods=["GET"])
def get_sdk_status(lang):
    if lang not in _sdk_status:
        return jsonify({"error": "unknown sdk"}), 404
    return jsonify(_sdk_status[lang])


@app.route("/api/sdk-status/<lang>", methods=["POST"])
def post_sdk_status(lang):
    if lang not in _sdk_status:
        return jsonify({"error": "unknown sdk"}), 404
    data = request.get_json(force=True)
    _sdk_status[lang] = {
        "status": data.get("status", "running"),
        "log": data.get("log", ""),
    }
    return jsonify({"ok": True})


@app.route("/api/sdk-trigger/<lang>", methods=["POST"])
def trigger_sdk(lang):
    if lang not in _sdk_trigger:
        return jsonify({"error": "unknown sdk"}), 404
    _sdk_trigger[lang] += 1
    _sdk_status[lang] = {"status": "pending", "log": ""}
    return jsonify({"ok": True, "generation": _sdk_trigger[lang]})


@app.route("/api/sdk-trigger/<lang>", methods=["GET"])
def get_sdk_trigger(lang):
    if lang not in _sdk_trigger:
        return jsonify({"error": "unknown sdk"}), 404
    return jsonify({"generation": _sdk_trigger[lang]})


_db_initialized = False


@app.before_request
def _ensure_db():
    """Initialize the database on the first request (works under gunicorn)."""
    global _db_initialized
    if not _db_initialized:
        wait_for_pg(max_retries=10, delay=3.0)
        init_db()
        _db_initialized = True


if __name__ == "__main__":
    print("Waiting for PostgreSQL to accept connections...")
    wait_for_pg()

    print("Initializing database schema...")
    try:
        init_db()
        _db_initialized = True
        print("Database ready.")
    except Exception as exc:
        print(f"ERROR: Could not initialize database: {exc}", file=sys.stderr)
        sys.exit(1)

    port = int(os.environ.get("PORT", "5001"))
    print(f"\n  Open http://localhost:{port} in your browser\n")
    app.run(host="0.0.0.0", port=port, debug=False)

"""Exercise the workflow's package downloads against actual HTTP error responses."""

import json
import os
import shutil
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[1]


def test_infra_change_in_a_large_diff_runs_every_sample(tmp_path):
    # build-matrix.sh runs with pipefail. When the list of changed files outgrew a pipe buffer, echo died of SIGPIPE
    # once grep -q had its match, the match read as a failure, and a pull request that changed an infrastructure
    # file among many others ran only some of the samples.
    for path in (
        "run-samples.sh",
        ".github/scripts/build-matrix.sh",
        ".github/workflows/run-samples.yml",
    ):
        destination = tmp_path / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, destination)

    def run(*args, **kwargs):
        return subprocess.check_output(args, cwd=tmp_path, text=True, **kwargs)

    def commit(message):
        run("git", "add", ".")
        run(
            "git",
            "-c",
            "user.name=CI",
            "-c",
            "user.email=ci@example.com",
            "commit",
            "-qm",
            message,
        )

    run("git", "init", "-q")
    commit("baseline")
    base = run("git", "rev-parse", "HEAD").strip()
    with (tmp_path / ".github/workflows/run-samples.yml").open("a") as workflow:
        workflow.write("\n# Workflow changed\n")
    # Enough other changed files for their list to exceed a 64 KiB pipe buffer
    other_files = tmp_path / "docs" / "large-change"
    other_files.mkdir(parents=True)
    for index in range(2000):
        (other_files / f"{index:04d}-{'x' * 60}.md").write_text("changed\n")
    commit("the workflow and many other files")
    output = tmp_path / "github-output"
    run(
        "bash",
        ".github/scripts/build-matrix.sh",
        "changed",
        base,
        "both",
        "Linux",
        env={**os.environ, "GITHUB_OUTPUT": str(output)},
    )

    matrix = json.loads(
        next(
            line.removeprefix("matrix=")
            for line in output.read_text().splitlines()
            if line.startswith("matrix=")
        )
    )
    samples = json.loads(run("bash", "run-samples.sh", "--list"))
    assert len(matrix["include"]) == sum(len(sample["arches"]) for sample in samples)


REPOSITORY = (
    b"deb [arch=amd64] https://packages.microsoft.com/ubuntu/22.04/prod jammy main\n"
)


@pytest.mark.parametrize("failure", [None, "transient", "persistent", "html", "key"])
def test_microsoft_repository_downloads(tmp_path, failure):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            source = self.path.endswith("prod.list")
            failed = (
                (source and failure == "persistent")
                or (
                    source and failure == "transient" and requests.count(self.path) == 1
                )
                or (not source and failure == "key")
            )
            self.send_response(429 if failed else 200)
            self.send_header("Retry-After", "1")
            self.end_headers()
            self.wfile.write(
                b"<!DOCTYPE html><html>The request is blocked.</html>"
                if failed or (source and failure == "html")
                else REPOSITORY
                if source
                else b"test signing key\n"
            )

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    # Keep privileged writes and package installation inside the test sandbox.
    sudo = bin_dir / "sudo"
    sudo.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, pathlib, shutil, sys\n"
        "root = pathlib.Path(os.environ['TEST_ROOT'])\n"
        "args = sys.argv[1:]\n"
        "with (root / 'actions').open('a') as f: f.write(json.dumps(args) + '\\n')\n"
        "if args[0] == 'tee':\n"
        "    p = root / args[1].lstrip('/'); p.parent.mkdir(parents=True, exist_ok=True)\n"
        "    data = sys.stdin.buffer.read(); p.write_bytes(data); sys.stdout.buffer.write(data)\n"
        "elif args[0] == 'install':\n"
        "    p = root / args[-1].lstrip('/'); p.parent.mkdir(parents=True, exist_ok=True)\n"
        "    shutil.copyfile(args[-2], p)\n"
        "elif args[0] == 'apt-get':\n"
        "    p = root / 'etc/apt/sources.list.d/mssql-release.list'\n"
        "    if p.exists() and not p.read_bytes().startswith(b'deb '): sys.exit(100)\n"
    )
    sudo.chmod(0o755)
    release = bin_dir / "lsb_release"
    release.write_text("#!/bin/sh\nprintf '22.04\\n'\n")
    release.chmod(0o755)
    workflow = yaml.safe_load((ROOT / ".github/workflows/run-samples.yml").read_text())
    step = next(
        step
        for step in workflow["jobs"]["scripts"]["steps"]
        if step.get("name") == "Install MSSQL ODBC and Tools"
    )
    script = (
        step["run"]
        .replace(
            "https://packages.microsoft.com", f"http://127.0.0.1:{server.server_port}"
        )
        .replace("--retry-delay 5", "--retry-delay 1")
    )
    env = dict(
        os.environ,
        PATH=f"{bin_dir}:{os.environ['PATH']}",
        TEST_ROOT=str(tmp_path),
        RUNNER_TEMP=str(tmp_path),
        GITHUB_PATH=str(tmp_path / "github-path"),
    )
    try:
        result = subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", script],
            env=env,
            text=True,
            capture_output=True,
            timeout=60,
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    source = tmp_path / "etc/apt/sources.list.d/mssql-release.list"
    action_log = tmp_path / "actions"
    actions = (
        [json.loads(line) for line in action_log.read_text().splitlines()]
        if action_log.exists()
        else []
    )
    if failure in ("persistent", "html", "key"):
        assert result.returncode != 0, result.stdout + result.stderr
        assert not source.exists(), (
            "An unsuccessful download must not change APT sources"
        )
        assert not any(action[0] == "apt-get" for action in actions)
    else:
        assert result.returncode == 0, result.stdout + result.stderr
        assert source.read_bytes() == REPOSITORY
        assert any("msodbcsql18" in action for action in actions)
        if failure == "transient":
            assert sum(path.endswith("prod.list") for path in requests) == 2

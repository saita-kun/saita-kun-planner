#!/bin/bash
# Reuse the archive suite for ordering, rollback, recovery and idempotence.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/tools/test-build-pack-archive.sh"
python3 -B - "$ROOT" <<'PY'
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from unittest import mock

root = pathlib.Path(sys.argv[1])
sid = "pack-fixture"
source = f"input/spec/{sid}/{sid}.json"
with tempfile.TemporaryDirectory(prefix="promote cli ") as directory:
    work = pathlib.Path(directory)
    pack = work / "input/spec" / sid
    shutil.copytree(root / "tools/fixtures/packs/green", pack)
    confirmation = pack / (sid + ".confirmation.json")
    value = json.loads(confirmation.read_text(encoding="utf-8"))
    value["spec_path"] = source
    confirmation.write_text(json.dumps(value), encoding="utf-8")
    manifest = pack / "pack.json"
    value = json.loads(manifest.read_text(encoding="utf-8"))
    value["confirmation"]["sha256"] = hashlib.sha256(confirmation.read_bytes()).hexdigest()
    manifest.write_text(json.dumps(value), encoding="utf-8")
    app = work / "input/current-application.json"
    app.write_text(json.dumps({"subsidy_id": sid, "spec_path": source,
                               "state": "spec_confirmed"}), encoding="utf-8")
    def snapshot():
        return {p.relative_to(work): p.read_bytes() for p in work.rglob("*") if p.is_file()}
    def run(args):
        return subprocess.run(["bash", str(root / "tools/promote-pack.sh")] + args,
                              cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True,
                              env=dict(os.environ, PLANNER_PYTHON=sys.executable,
                                       PYTHONDONTWRITEBYTECODE="1"))
    sys.path.insert(0, str(root / "tools/lib"))
    from promote_pack import copy_exclusive
    destination = work / "partial-copy"
    original_open = pathlib.Path.open
    def broken_write(path, mode):
        stream = original_open(path, mode)
        class BrokenStream:
            def __enter__(self):
                return self
            def write(self, data):
                stream.write(data[:1])
                raise OSError("partial write")
            def __exit__(self, *args):
                stream.close()
        return BrokenStream()
    with mock.patch.object(pathlib.Path, "open", new=broken_write):
        try:
            copy_exclusive(destination, b"original")
        except OSError:
            pass
        else:
            raise AssertionError("partial copy must fail")
    assert not destination.exists()
    before = snapshot()
    for args in ([], [sid], [sid, source, "extra"], [sid, source, "--bad", str(work)],
                 ["../bad", source], [sid, "../outside.json"], [sid, "/absolute.json"],
                 [sid, "input//spec/pack-fixture.json"], [sid, source, "--root", str(work / "missing")]):
        result = run(args)
        assert result.returncode != 0 and "FAIL:" in result.stderr, (args, result.stderr)
        assert snapshot() == before
    for args in ([sid, source, "--root", str(work)], [sid, source]):
        result = run(args)
        assert result.returncode == 0, result.stdout + result.stderr
        assert result.stdout.splitlines()[-1] == "OK: verified pack selected: " + source
        assert snapshot() == before
print("PASS: promotion CLI arguments, external root and selected-pack idempotence")
PY
